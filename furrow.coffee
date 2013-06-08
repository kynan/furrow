if Meteor.isClient
  Accounts.ui.config
    requestPermissions:
      google: ['https://www.googleapis.com/auth/plus.login', 'https://www.googleapis.com/auth/userinfo.email']
  Meteor.startup ->
    Deps.autorun (c) ->
      if Meteor.user()
        console.log Meteor.user()
        Meteor.http.get 'https://www.googleapis.com/plus/v1/people/me/people/visible?access_token=' + Meteor.user().services.google.accessToken, (err, res) ->
          Meteor._debug err if err?
          if !err
            Session.set("friendslist", res.data.items)
    Template.friendslist.friends = () ->
      Session.get("friendslist")

if Meteor.isServer
  Meteor.startup ->

# code to run on server at startup
