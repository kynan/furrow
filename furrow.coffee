if Meteor.isClient
  Accounts.ui.config
    requestPermissions:
      google: ['https://www.googleapis.com/auth/plus.login', 'https://www.googleapis.com/auth/userinfo.email']
    requestOfflineToken: true
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
      if Meteor.user()
        console.log Meteor.user()
        getFriendsList Meteor.user().services.google.accessToken
    Template.friendslist.friends = () ->
      Session.get("friendslist")

if Meteor.isServer
  Meteor.startup ->

# code to run on server at startup
