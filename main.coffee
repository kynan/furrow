ConnectionRequests = new Meteor.Collection "connection_requests"
Mood = new Meteor.Collection "mood"

if Meteor.isClient
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
  getGoogleContactList = (token) ->
    url = 'https://www.googleapis.com/plus/v1/people/me/people/visible'
    Meteor.http.get "#{url}?access_token=#{token}", (err, res) ->
      Meteor._debug err if err?
      if !err?
        contacts = res.data.items
        # Check whether any of your contacts is already registered
        for contact in contacts
          user = Meteor.users.findOne 'services.google.id': contact.id
          contactStatus user, contact if user
        Session.set("contactlist", contacts)
        return Session.set("friendslist", (c for c in contacts when c.is_friend))
      # Log out if auth token has expired; should no longer be necessary once
      # https://github.com/meteor/meteor/pull/522 is merged
      if err.response.statusCode == 401 or err.response.statusCode == 403
        Meteor.Error err.response.statusCode, 'Failed to get Google contacts list', err.response
  getFacebookContactList = (token) ->
    url = 'https://graph.facebook.com/me/friends'
    Meteor.http.get "#{url}?access_token=#{token}", (err, res) ->
      Meteor._debug err if err?
      if !err?
        contacts = res.data.data
        # Check whether any of your contacts is already registered
        for contact in contacts
          user = Meteor.users.findOne 'services.facebook.id': contact.id
          contactStatus user, contact if user
          contact.url = "https://facebook.com/#{contact.id}"
          contact.image =
            url: "http://graph.facebook.com/#{contact.id}/picture"
        Session.set("contactlist", contacts)
        console.log 'Facebook contacts', contacts
        return Session.set("friendslist", (c for c in contacts when c.is_friend))
      if err.response.statusCode == 401 or err.response.statusCode == 403
        Meteor.Error err.response.statusCode, 'Failed to get Google contacts list', err.response

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

  Meteor.startup ->
    Deps.autorun (c) ->
      user = Meteor.user()
      if Meteor.user()
        console.log user
        if user.services?.google?.accessToken?
          getGoogleContactList user.services.google.accessToken
        if user.services?.facebook?.accessToken?
          getFacebookContactList user.services.facebook.accessToken
        Meteor.subscribe "connection_requests"
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
    Template.peoplelist.events =
      'click button.connect': (evt, template) ->
        console.log evt, template
        ConnectionRequests.insert
          userId: evt.target.id
          requester: Meteor.user().profile
      'click button.unfriend': (evt, template) ->
        console.log 'unfriend', evt, template
        Meteor.users.update _id: Meteor.userId(), {$pull: {friends: evt.target.id}}
    Template.notifications.connectionRequests = () ->
      ConnectionRequests.find userId: Meteor.userId()
    Template.notifications.events =
      'click button.accept': (evt, template) ->
        console.log 'accept', evt, template
        Meteor.users.update _id: evt.target.id, {$addToSet: {friends: Meteor.userId()}}
        ConnectionRequests.remove evt.target.attributes.requestId.value
    Template.setmood.events =
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
    Template.invitefriends.events =
      'click button.search': (evt, template) ->
        evt.preventDefault()
        potentialusers = Meteor.users.find({
          'profile.name': new RegExp(template.find('#name').value) }, {limit: 10}).fetch()
        me = Meteor.user()
        potentialusers.filter (user) -> user != me
        console.log potentialusers
        Session.set('people',potentialusers)
     Template.peoplelist.friends = () ->
       if Meteor.Router.page() == 'invitefriends'
         value = Session.get('people')
       else
         value = Session.get("contactlist")
       console.log value 
       return value

if Meteor.isServer
  getGoogleProfile = (user) ->
    url = 'https://www.googleapis.com/plus/v1/people/me'
    res = Meteor.http.get "#{url}?access_token=#{user.services.google.accessToken}"
    if res.statusCode == 200
      console.log 'Google profile', res
      # The google profile has a name attribute with a nested hash of
      # {familyName: ..., givenName: ...}, so we need to rename that, since
      # it's being used in the Metor displayName template helper
      res.data.fullName = res.data.name
      delete res.data.name
      return res.data
    else
      Meteor._debug res.data
      Meteor.Error res.statusCode, 'Failed to get Google profile', res.data
  getFacebookProfile = (user) ->
    url = 'https://graph.facebook.com/me'
    res = Meteor.http.get "#{url}?access_token=#{user.services.facebook.accessToken}"
    if res.statusCode == 200
      console.log 'Facebook profile', res
      # The google profile has a name attribute with a nested hash of
      # {familyName: ..., givenName: ...}, so we need to rename that, since
      # it's being used in the Metor displayName template helper
      res.data.fullName = res.data.name
      res.data.image =
        url: "http://graph.facebook.com/#{res.data.id}/picture?type=large"
      delete res.data.name
      return res.data
    else
      Meteor._debug res.data
      Meteor.Error res.statusCode, 'Failed to get Facebook profile', res.data
  Accounts.onCreateUser (options, user) ->
    # FIXME: eventually we want to make sure to consolidate profiles with the
    # same email address
    console.log 'onCreateUser', options, user
    profile = options.profile || {}
    if user.services?.password?
      profile = options.profile || {}
      profile.name = user.username
      user.name = user.username
    if user.services?.google?.accessToken?
      _.extend profile, getGoogleProfile user
    if user.services?.facebook?.accessToken?
      _.extend profile, getFacebookProfile user
    user.profile = profile
    console.log 'onCreateUser end', options, user
    return user
  # Publish the services and createdAt fields from the users collection to the client
  Meteor.publish null, ->
    Meteor.users.find {}, {fields: {services: 1, createdAt: 1, friends: 1, profile: 1}}
  Meteor.publish "connection_requests", ->
    ConnectionRequests.find {$or: [{userId: @userId}, {'requester._id': @userId}]}
  Meteor.publish "mood", (users)->
    check(users, Array)
    Mood.find userId: {$in: users}
  Meteor.users.allow
    update: (userId, doc) ->
      console.log userId, doc
      return userId == doc._id or ConnectionRequests.findOne userId: userId
