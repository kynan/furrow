ConnectionRequests = new Meteor.Collection "connection_requests"

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
        friends = res.data.items
        # Check whether any of your friends is already registered
        for friend in friends
          user = Meteor.users.findOne 'services.google.id': friend.id
          friend._id = user._id if user
          console.log friend if user
        return Session.set("friendslist", friends)
      # Log out if auth token has expired; should no longer be necessary once
      # https://github.com/meteor/meteor/pull/522 is merged
      if err.response.statusCode == 401 or err.response.statusCode == 403
        Meteor.logout()

  Meteor.startup ->
    Deps.autorun (c) ->
      user = Meteor.user()
      if user
        console.log user
        if user.services?.google?.accessToken?
          getFriendsList user.services.google.accessToken
          getProfile user.services.google.accessToken
        Meteor.subscribe "connection_requests"
    Template.friendslist.friends = () ->
      Session.get("friendslist")
    Template.friendslist.events =
      'click button.connect': (evt, template) ->
        console.log evt, template
        ConnectionRequests.insert
          userId: evt.target.id
          requester: Session.get("profile")

if Meteor.isServer
  # Publish the services and createdAt fields from the users collection to the client
  Meteor.publish null, ->
    Meteor.users.find {}, {fields: {'services': 1, 'createdAt': 1}}
  Meteor.publish "connection_requests", ->
    ConnectionRequests.find userId: @userId
