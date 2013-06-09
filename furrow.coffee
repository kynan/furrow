ConnectionRequests = new Meteor.Collection "connection_requests"
Mood = new Meteor.Collection "mood"

if Meteor.isClient
  Accounts.ui.config
    requestPermissions:
      google: ['https://www.googleapis.com/auth/plus.login', 'https://www.googleapis.com/auth/userinfo.email']
    requestOfflineToken: true
  getProfile = (token) ->
    url = 'https://www.googleapis.com/plus/v1/people/me'
    Meteor.http.get "#{url}?access_token=#{token}", (err, res) ->
      Meteor._debug err if err?
      console.log res
      profile = res.data
      profile._id = Meteor.userId()
      Session.set("profile", res.data)
  getFriendsList = (token) ->
    url = 'https://www.googleapis.com/plus/v1/people/me/people/visible'
    Meteor.http.get "#{url}?access_token=#{token}", (err, res) ->
      Meteor._debug err if err?
      if !err?
        me = Meteor.user()
        friends = res.data.items
        # Check whether any of your friends is already registered
        for friend in friends
          user = Meteor.users.findOne 'services.google.id': friend.id
          if user
            friend._id = user._id
            friend.is_friend = user._id in me.friends if me.friends
            friend.is_following = me._id in user.friends if user.friends
            console.log friend
        return Session.set("friendslist", friends)
      # Log out if auth token has expired; should no longer be necessary once
      # https://github.com/meteor/meteor/pull/522 is merged
      if err.response.statusCode == 401 or err.response.statusCode == 403
        Meteor.logout()

  Meteor.startup ->
    Deps.autorun (c) ->
      user = Meteor.user()
      if Meteor.user()
        console.log user
        if user.services?.google?.accessToken?
          getFriendsList user.services.google.accessToken
          getProfile user.services.google.accessToken
        Meteor.subscribe "connection_requests"
        if user.friends
          Meteor.subscribe "mood", user.friends
          moods = (Mood.findOne {userId: friend}, {sort: {createdAt: -1}} for friend in Meteor.user().friends)
          console.log 'moods', moods
          Session.set "moods", moods
    Template.friendslist.friends = () ->
      Session.get("friendslist")
    Template.friendslist.events =
      'click button.connect': (evt, template) ->
        console.log evt, template
        ConnectionRequests.insert
          userId: evt.target.id
          requester: Session.get("profile")
      'click button.unfriend': (evt, template) ->
        console.log 'unfriend', evt, template
        Meteor.users.update _id: Meteor.userId(), {$pull: {friends: evt.target.id}}
    Template.notifications.connectionRequests = () ->
      ConnectionRequests.find()
    Template.notifications.events =
      'click button.accept': (evt, template) ->
        console.log 'accept', evt, template
        Meteor.users.update _id: evt.target.id, {$addToSet: {friends: Meteor.userId()}}
        ConnectionRequests.remove evt.target.attributes.requestId.value
    Template.setmood.events =
      'submit form#setmood': (evt, template) ->
        console.log 'set mood', evt, template
        evt.preventDefault()
        Mood.insert
          userId: Meteor.userId()
          mood: template.find("select#mood").value
          message: template.find("input#message").value
          createdAt: Date.now()
        evt.target.reset()
    Template.mood.moods = () ->
      Session.get "moods"

if Meteor.isServer
  # Publish the services and createdAt fields from the users collection to the client
  Meteor.publish null, ->
    Meteor.users.find {}, {fields: {services: 1, createdAt: 1, friends: 1}}
  Meteor.publish "connection_requests", ->
    ConnectionRequests.find userId: @userId
  Meteor.publish "mood", (users)->
    check(users, Array)
    Mood.find userId: {$in: users}
  Meteor.users.allow
    update: (userId, doc) ->
      console.log userId, doc
      return userId == doc._id or ConnectionRequests.findOne userId: userId
