'use strict'
import util from 'util'
import canonical from '/lib/imports/canonical.coffee'
import { newMessage } from './newMessage.coffee'

escape =
  '&': '&amp;'
  '<': '&lt;'
  '>': '&gt;'

export default install = (rtm, channel) ->
  if channel.startsWith '#'
    channel = do ->
      norm = channel.substring 1
      args = {}
      loop
        res = Promise.await rtm.webClient.users.conversations args
        args.cursor = res.response_metadata.next_cursor
        for chan in res.channels
          return chan.id if chan.name_normalized is norm
        throw new Error("Not member of channel named #{channel}") unless args.cursor
  handle = share.model.Messages.find
    timestamp: $gt: share.model.UTCNow()
    presence: null
    to: null
    system: null
    tweet: null
    room_name: 'general/0'
    'slack.timestamp': null
  .observeChanges
    added: (id, msg) ->
      try
        body = if msg.action
          "*#{msg.nick} #{msg.body}*"
        else
          "<#{msg.nick}> #{msg.body}"
        body = body.replace /[&<>]/g, (c) -> escape[c]
        reply = Promise.await rtm.sendMessage body, channel
        share.model.Messages.update id,
          $set: 'slack.timestamp': reply.ts
      catch e
        console.warn 'Error posting to Slack', e
  messageHandler = Meteor.bindEnvironment (message) ->
    return unless message.channel is channel
    return if message.hidden
    
    usersNeeded = new Set [message.user]
    channelsNeeded = new Set
    richText = message.blocks?.find (block) -> block.type is 'rich_text'
    if richText?
      for element1 in richText.elements
        for element2 in element1.elements
          usersNeeded.add element2.user_id if element2.type is 'user'
          channelsNeeded.add element2.channel_id if element2.type is 'channel'
    nicks = new Map
    channels = new Map
    # First lookup in Users table; only go to Slack if they're not already there.
    Meteor.users.find(slack_id: $in: Array.from usersNeeded).forEach (user) ->
      nicks.set user.slack_id,
        canon: user._id
        nickname: user.nickname
      usersNeeded.delete user.slack_id
    # Then get everything that's left from slack.
    promises = []
    usersNeeded.forEach (user) ->
      promises.push do ->
        res = await rtm.webClient.users.info {user}
        return unless res.ok
        nicks.set res.user.id,
          canon: canonical(res.user.name)
          nickname: res.user.name
        doc = nickname: res.user.name
        if res.user.name isnt res.user.real_name
          doc.real_name = res.user.real_name
        if res.user.profile?.email?
          doc.gravatar = res.user.profile.email
        Meteor.users.upsert canonical(res.user.name),
          $set: slack_id: res.user.id
          $setOnInsert: doc
    channelsNeeded.forEach (channel) ->
      promises.push do ->
        res = await rtm.webClient.conversations.info {channel}
        return unless res.ok
        channels.set channel, res.channel.name
    Promise.await Promise.all promises
    msg =
      body: ''
      nick: nicks.get(message.user).canon
      room_name: 'general/0'
      slack:
        timestamp: message.ts
        from_slack: true
    if richText?
      for element1 in richText.elements
        for element2 in element1.elements
          switch element2.type
            when 'text'
              msg.body += element2.text
            when 'user'
              msg.body += nicks.get(element2.user_id).nickname
            when 'broadcast'
              msg.body += "@#{element2.range}"
            when 'emoji'
              msg.body += ":#{element2.name}:"
            when 'channel'
              msg.body += "##{channels.get element2.channel_id}"
            else
              console.log element2
    else if message.subtype is 'me_message'
      msg.action = true
      text = message.text.replace /<!([a-z]*)>/gi, '@$1'
      msg.body = text.replace /<@[a-z0-9]*\|([_a-z0-9]*)>/gi, '$1'
    newMessage msg    

  rtm.on 'message', messageHandler
  return
    stop: ->
      rtm.removeListener 'message', messageHandler
      handle.stop()
