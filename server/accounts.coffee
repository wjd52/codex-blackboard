'use strict'
import canonical from '../lib/imports/canonical.coffee'
import { StringWithLength } from '../lib/imports/match.coffee'

PASSWORD = Meteor.settings?.password ? process.env.TEAM_PASSWORD 

Meteor.users.deny
  update: -> true

Accounts.registerLoginHandler 'codex', (options) ->
  check options,
    nickname: String
    real_name: String
    gravatar: String
    password: String
  unless Match.test options.nickname, StringWithLength(min: 1, max: 20)
    throw new Meteor.Error 401, "Nickname must be 1-20 characters long", field: 'nickname'
  unless Match.test options.real_name, StringWithLength(max: 100)
    throw new Meteor.Error 401, "Real name must be at most 100 characters", field: 'real_name'
  unless Match.test options.gravatar, StringWithLength(max: 100)
    throw new Meteor.Error 401, "Email address for gravatar must be at most 100 characters", field: 'gravatar'

  if PASSWORD?
    unless options.password is PASSWORD
      throw new Meteor.Error 401, 'Wrong password', field: 'password'

  canon = canonical options.nickname

  profile = nickname: options.nickname
  profile.gravatar = options.gravatar if options.gravatar
  profile.real_name = options.real_name if options.real_name

  # If you have the team password, we'll create an account for you.
  try
    Meteor.users.upsert
      _id: canon
      bot_wakeup: $exists: false
    , $set: profile
  catch error
    throw new Meteor.Error 401, 'Can\'t impersonate the bot', field: 'nickname'

  return { userId: canon }
