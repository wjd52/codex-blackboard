'use strict' 

import { RTMClient } from '@slack/rtm-api'
import install from './imports/slack.coffee'

return unless share.DO_BATCH_PROCESSING
settings = Meteor.settings?.slack ? {}
access_token = settings.access_token ? process.env.SLACK_ACCESS_TOKEN
return unless access_token?
channel = settings.channel ? process.env.SLACK_CHANNEL ? '#general'
Meteor.startup ->
  rtm = new RTMClient access_token
  rtm.start()
  Promise.await install rtm, channel
