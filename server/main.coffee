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
    res.data.url = res.data.link
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
  user.name = profile.name
  user.url = profile.url || ''
  user.image = profile.image || url: 'http://b.static.ak.fbcdn.net/rsrc.php/v1/yo/r/UlIqmHJn-SK.gif'
  console.log 'onCreateUser end', options, user
  return user
Meteor.methods
  refreshOAuthToken: (service) ->
    getNewAccessToken = (service) ->
      result = Meteor.http.post(service.url, {headers: {'Content-Type': 'application/x-www-form-urlencoded'}, content: oAuthRefreshBody(service)})
      return result.data?.access_token
    oAuthRefreshBody = (service) ->
      loginServiceConfig = Accounts.loginServiceConfiguration.findOne({service: service.name});
      return 'refresh_token=' + Meteor.user().services[service.name].refreshToken +
          '&client_id=' + loginServiceConfig.clientId +
          '&client_secret=' + loginServiceConfig.secret +
          '&grant_type=refresh_token'
    storeNewAccessToken = (service, newAccessToken) ->
      o = {}
      o['services.' + service.name + '.accessToken'] = newAccessToken
      Meteor.users.update Meteor.userId(), {$set: o}
    token = getNewAccessToken service
    console.log "Got new access token #{token} for", service
    storeNewAccessToken service, token
    return token

# Publish the services and createdAt fields from the users collection to the client
Meteor.publish null, ->
  Meteor.users.find {}, {fields: {services: 1, createdAt: 1, friends: 1, profile: 1, name: 1, image: 1, url: 1}}
Meteor.publish "connection_requests", ->
  ConnectionRequests.find {$or: [{userId: @userId}, {'requester._id': @userId}]}
Meteor.publish "mood", (users)->
  check(users, Array)
  Mood.find userId: {$in: users}
Meteor.users.allow
  update: (userId, doc) ->
    return userId == doc._id or ConnectionRequests.findOne userId: userId
