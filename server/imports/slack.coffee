'use strict'

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
        res = Promise.await rtm.webClient.apiCall 'users.conversations', args
        args.cursor = res.response_metadata.next_cursor
        for chan in res.channels
          return chan.id if chan.name_normalized is norm
        throw new Error("Not member of channel named #{channel}") unless args.cursor
  share.model.Messages.find
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
