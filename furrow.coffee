if Meteor.isClient
  Meteor.startup ->
    Template.hello.greeting = ->
      "Welcome to furrow."

    Template.hello.events "click input": ->
      # template data, if any, is available in 'this'
      console.log "You pressed the button"

if Meteor.isServer
  Meteor.startup ->


# code to run on server at startup
