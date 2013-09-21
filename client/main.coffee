Accounts.ui.config
  requestPermissions:
    google: ['https://www.googleapis.com/auth/plus.login', 'https://www.googleapis.com/auth/userinfo.email']
    facebook: ['email', 'read_friendlists', 'read_stream', 'user_photos', 'user_relationships', 'user_status']
  requestOfflineToken:
    google: true
  passwordSignupFields: 'USERNAME_AND_EMAIL'
contactStatus = (user, contact) ->
  me = Meteor.user()
  contact._id = user._id
  contact.is_friend = user._id in me.friends if me.friends
  contact.is_following = me._id in user.friends if user.friends
  contact.is_invited = ConnectionRequests.findOne {'requester._id': me._id, userId: user._id}
  return contact
getGoogleContactList = (token) ->
  url = 'https://www.googleapis.com/plus/v1/people/me/people/visible'
  HTTP.get "#{url}?access_token=#{token}", (err, res) ->
    Meteor._debug err if err?
    if !err?
      contacts = Session.get("contactlist") || []
      contactids = (x.google_id for x in contacts)
      # Check whether any of your contacts is already registered
      for contact in res.data.items
        if !(contact.id in contactids)
          user = Meteor.users.findOne 'services.google.id': contact.id
          contact = contactStatus user, contact if user
          contact.google_id = contact.id
          contact.name = contact.displayName
          contacts.push contact
      Session.set("contactlist", contacts)
      console.log 'Google contacts', contacts
      return Session.set("friendslist", (c for c in contacts when c.is_friend))
    report = (err) ->
      Meteor.Error err.response.statusCode, 'Failed to get Google contacts list', err.response
    if err.response.statusCode == 401
      # Refresh OAuth token if it has expired. Simplified version of
      # https://github.com/meteor/meteor/pull/522
      Meteor.call 'refreshOAuthToken',
        {name: 'google', url: 'https://accounts.google.com/o/oauth2/token'},
        (err, token) ->
          getGoogleContactList token if !err
          report err if err
    else
      report err
getFacebookContactList = (token) ->
  url = 'https://graph.facebook.com/me/friends'
  HTTP.get "#{url}?access_token=#{token}", (err, res) ->
    Meteor._debug err if err?
    if !err?
      contacts = Session.get("contactlist") || []
      contactids = (x.facebook_id for x in contacts)
      # Check whether any of your contacts is already registered
      for contact in res.data.data
        if !(contact.id in contactids)
          user = Meteor.users.findOne 'services.facebook.id': contact.id
          contact = contactStatus user, contact if user
          contact.facebook_id = contact.id
          contact.url = "https://facebook.com/#{contact.id}"
          contact.image =
            url: "http://graph.facebook.com/#{contact.id}/picture"
          contacts.push contact
      Session.set("contactlist", contacts)
      console.log 'Facebook contacts', contacts
      return Session.set("friendslist", (c for c in contacts when c.is_friend))
    if err.response.statusCode == 401 or err.response.statusCode == 403
      Meteor.Error err.response.statusCode, 'Failed to get Google contacts list', err.response

# FIXME: This should really be a method on the server
setContactsFromFriends = (friends) ->
  #user may not have a contactlist if they are using a password account
  contacts = Session.get("contactlist") || []
  changed = false
  for friend in friends
    if !(friend in (contact._id for contact in contacts))
      changed = true
      user = Meteor.users.findOne(_id: friend)
      contact = user
      contact = contactStatus user, contact
      contacts.push contact
  #needed to prevent an infinite loop where session.set triggers this method
  if changed
    Session.set("contactlist",contacts)

Meteor.Router.filters
  requireLogin: (page) ->
    if Meteor.user()
      return page
    else
      return 'welcome'

Meteor.Router.filter 'requireLogin', except: 'welcome'

Meteor.Router.add
  '/': 'mood'
  '/mood': 'mood'
  '/friends': 'friendslist'
  '/edit': 'setmood'
  '/welcome': 'welcome'
  '/invitefriends': 'invitefriends'

Template.peoplelist.events
  'click button.connect': (evt, template) ->
    console.log 'connect', evt, template
    requester = Meteor.user().profile
    requester._id = Meteor.userId()
    ConnectionRequests.insert
      userId: evt.target.id
      requester: requester
    #contactlist is not always defined for users
    #who have not imported contacts
    contacts = Session.get("contactlist") || []
    if !(evt.target.id in (contact._id for contact in contacts))
      contact = Meteor.users.findOne '_id': evt.target.id
      contact = contactStatus contact, contact
      contacts.push contact
      Session.set("contactlist", contacts)
  'click button.unfriend': (evt, template) ->
    console.log 'unfriend', evt, template
    Meteor.users.update _id: Meteor.userId(), {$pull: {friends: evt.target.id}}
    #force update of status for contact removed
    contacts = Session.get("contactlist")
    contacts = (contactStatus contact, contact for contact in contacts when contact._id == evt.target.id)
    Session.set("contactlist")
Template.notifications.connectionRequests = () ->
  ConnectionRequests.find userId: Meteor.userId()
Template.notifications.events
  'click button.accept': (evt, template) ->
    console.log 'accept', evt, template
    Meteor.users.update _id: evt.target.id, {$addToSet: {friends: Meteor.userId()}}
    ConnectionRequests.remove evt.target.attributes.requestId.value
Template.setmood.events
  'click a.submit': (evt, template) ->
    console.log 'set mood', evt, template
    evt.preventDefault()
    Mood.insert
      userId: Meteor.userId()
      mood: template.find("select#mood").value
      message: template.find("input#message").value
      createdAt: Date.now()
    Meteor.Router.to '/mood'
Template.mood.moods = () ->
  Session.get "moods"
Template.invitefriends.events
  'click button.search': (evt, template) ->
    evt.preventDefault()
    # FIXME: This should really be a method on the server
    potentialusers = Meteor.users.find({
      'profile.name': new RegExp(template.find('#name').value) }, {limit: 10}).fetch()
    me = Meteor.user()
    potentialusers = potentialusers.filter (user) -> user._id != me._id
    Session.set('people',potentialusers)
Template.peoplelist.friends = () ->
  if Meteor.Router.page() == 'invitefriends'
    return Session.get('people')
  else
    return Session.get("contactlist")

Deps.autorun (c) ->
  user = Meteor.user()
  if user and not Session.get 'contactlist'
    if user.services?.google?.accessToken?
      getGoogleContactList user.services.google.accessToken
    if user.services?.facebook?.accessToken?
      getFacebookContactList user.services.facebook.accessToken
    Meteor.subscribe "connection_requests"
    Meteor.subscribe "connection_responses"
    if user.friends
      Meteor.subscribe "mood", user.friends
      getMood = (friend) ->
        # FIXME: This should really be a method on the server
        profile = Meteor.users.findOne(_id: friend).profile
        profile.mood = Mood.findOne {userId: friend}, {sort: {createdAt: -1}}
        if profile.mood?.createdAt?
          profile.mood.modified = humanized_time_span profile.mood.createdAt
        return profile
      moods = (getMood friend for friend in Meteor.user().friends)
      console.log 'moods', moods
      Session.set "moods", moods
      setContactsFromFriends user.friends
  else if not user
    Session.set "moods", undefined
    Session.set "friendslist", undefined
    Session.set "contactlist", undefined
