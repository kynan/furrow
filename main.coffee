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
            friend.is_invited = ConnectionRequests.findOne {'requester._id': me._id, userId: user._id}
            console.log friend
        Session.set("contactlist", friends)
        return Session.set("friendslist", (f for f in friends when f.is_friend))
      # Log out if auth token has expired; should no longer be necessary once
      # https://github.com/meteor/meteor/pull/522 is merged
      if err.response.statusCode == 401 or err.response.statusCode == 403
        Meteor.logout()

  Meteor.startup ->
    Session.set 'pane', 'mood'
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
          getMood = (friend) ->
            friend.mood = Mood.findOne {userId: friend._id}, {sort: {createdAt: -1}}
            if friend.mood?.createdAt?
              friend.mood.modified = humanized_time_span friend.mood.createdAt
            return friend
          moods = (getMood friend for friend in Session.get "friendslist")
          console.log 'moods', moods
          Session.set "moods", moods
    Template.friendslist.friends = () ->
      Session.get("contactlist")
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
        Session.set 'pane', 'mood'
    Template.mood.moods = () ->
      Session.get "moods"
    Template.main.editpane = () ->
      Session.equals 'pane', 'edit'
    Template.main.friendspane = () ->
      Session.equals 'pane', 'friends'
    Template.main.moodpane = () ->
      Session.equals 'pane', 'mood'
    Template.main.events =
      'click a.mood': () ->
        Session.set 'pane', 'mood'
      'click a.friends': () ->
        Session.set 'pane', 'friends'
      'click a.edit': () ->
        Session.set 'pane', 'edit'
      'click a.close': (evt, template) ->
        Session.set 'pane', 'mood'

if Meteor.isServer
  # Publish the services and createdAt fields from the users collection to the client
  Meteor.publish null, ->
    Meteor.users.find {}, {fields: {services: 1, createdAt: 1, friends: 1}}
  Meteor.publish "connection_requests", ->
    ConnectionRequests.find {$or: [{userId: @userId}, {'requester._id': @userId}]}
  Meteor.publish "mood", (users)->
    check(users, Array)
    Mood.find userId: {$in: users}
  Meteor.users.allow
    update: (userId, doc) ->
      console.log userId, doc
      return userId == doc._id or ConnectionRequests.findOne userId: userId