if Meteor.isClient
  Accounts.ui.config
    requestPermissions:
      google: ['https://www.googleapis.com/auth/plus.login', 'https://www.googleapis.com/auth/userinfo.email']
    requestOfflineToken: true
  getFriendsList = (token) ->
    url = 'https://www.googleapis.com/plus/v1/people/me/people/visible'
    Meteor.http.get "#{url}?access_token=#{token}", (err, res) ->
      Meteor._debug err if err?
      Session.set("friendslist", res.data.items) if !err?
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
