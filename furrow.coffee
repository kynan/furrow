if Meteor.isClient
  Meteor.startup ->
    Template.hello.greeting = ->
      "Welcome to furrow."

    Template.hello.events "click input": ->
      # template data, if any, is available in 'this'
      console.log "You pressed the button"

    Template.auth.events
      "click #login": (evt) ->
        Meteor.loginWithGoogle (err) ->
          Meteor._debug err  if err

        evt.preventDefault()

      "click #logout": (evt) ->
        Meteor.logout (err) ->
          Meteor._debug err  if err

        evt.preventDefault()

if Meteor.isServer
  Meteor.startup ->


# code to run on server at startup
