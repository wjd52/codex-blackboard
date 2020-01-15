'use strict'

# Will access contents via share
import '/lib/model.coffee'
import chai from 'chai'
import sinon from 'sinon'
import { resetDatabase } from 'meteor/xolvio:cleaner'
import install from './slack.coffee'
import { WebClient } from '@slack/web-api'
import EventEmitter from 'events'
import delay from 'delay'
import { waitForDocument } from '../imports/testutils.coffee'

describe 'slack', ->
  clock = null
  beforeEach ->
    resetDatabase()
    clock = sinon.useFakeTimers
      now: 7
      toFake: ["Date"]

  afterEach ->
    clock.restore()

  fakeRtm = null
  rtmMock = null
  stubUsers = null
  stubConversations = null

  beforeEach ->
    fakeRtm = new EventEmitter
    fakeRtm.sendMessage = ->
    rtmMock = sinon.mock fakeRtm
    fakeRtm.webClient = new WebClient
    stubUsers = sinon.stub fakeRtm.webClient.users
    stubConversations = sinon.stub fakeRtm.webClient.conversations

  afterEach ->
    sinon.verifyAndRestore()

  handle = null
  afterEach ->
    handle?.stop()

  it 'looks up #channel', ->
    stubUsers.conversations.rejects().withArgs({}).resolves
      ok: true
      channels: [
        {
          id: 'C0123456'
          name_normalized: 'general'
        }
      ]
      response_metadata: {next_cursor: ''}
    handle = install fakeRtm, '#general'

  it 'fails if no #channel', ->
    stubUsers.conversations.rejects().withArgs({}).resolves
      ok: true
      channels: [
        {
          id: 'C0123456'
          name_normalized: 'general'
        }
      ]
      response_metadata: {next_cursor: ''}
    chai.assert.throws ->
      handle = install fakeRtm, '#frumious'
    , Error

  it 'paginates', ->
    stubUsers.conversations.rejects().withArgs({}).resolves
      ok: true
      channels: [
        {
          id: 'C0123456'
          name_normalized: 'general'
        }
      ]
      response_metadata: {next_cursor: 'abcde'}
    .withArgs(cursor: 'abcde').resolves
      ok: true
      channels: [
        {
          id: 'C1234567'
          name_normalized: 'frumious'
        }
      ]
      response_metadata: {next_cursor: ''}
    handle = install fakeRtm, '#frumious'

  describe 'on blackboard message', ->
    beforeEach ->
      handle = install fakeRtm, 'C1234567'

    it 'ignores from other room', ->
      rtmMock.expects('sendMessage').never()
      share.model.Messages.insert
        room_name: 'callins/0'
        nick: 'torgen'
        body: 'something'
        timestamp: 8
      delay 200

    it 'mirrors message from general room', ->
      rtmMock.expects('sendMessage').once().withArgs('&lt;torgen&gt; something', 'C1234567').resolves(ts: '123456.7890')
      id = share.model.Messages.insert
        room_name: 'general/0'
        nick: 'torgen'
        body: 'something'
        timestamp: 8
      waitForDocument share.model.Messages,
        _id: id
        'slack.timestamp': '123456.7890'
      , {}

    it 'mirrors action from general room', ->
      rtmMock.expects('sendMessage').once().withArgs('*torgen somethings*', 'C1234567').resolves(ts: '123456.7890')
      id = share.model.Messages.insert
        room_name: 'general/0'
        nick: 'torgen'
        body: 'somethings'
        action: true
        timestamp: 8
      waitForDocument share.model.Messages,
        _id: id
        'slack.timestamp': '123456.7890'
      , {}
      
  describe 'on slack message', ->
    beforeEach ->
      handle = install fakeRtm, 'C1234567'

    it 'ignores in wrong channel', ->
      fakeRtm.emit 'message',
        client_msg_id: '6c09236b-9dea-44b7-8421-b3a572e4f64c'
        suppress_notification: false
        type: 'message'
        text: 'yellow'
        user: 'USCTBT8DA'
        blocks: [ {
          type: 'rich_text'
          block_id: 'SNqrC'
          elements: [ {
            type: 'rich_text_section'
            elements: [ { type: 'text', text: 'yellow' } ] } ] } ]
        thread_ts: '1578899128.005200'
        user_team: 'TS1T1DGV9'
        source_team: 'TS1T1DGV9'
        channel: 'CSDBDN0JC'
        event_ts: '1578899141.005500'
        ts: '1578899141.005500'
      await delay 200
      chai.assert.lengthOf share.model.Messages.find().fetch(), 0

    it 'ignores hidden', ->
      fakeRtm.emit 'message',
        client_msg_id: '6c09236b-9dea-44b7-8421-b3a572e4f64c'
        suppress_notification: false
        type: 'message'
        text: 'yellow'
        hidden: true
        user: 'USCTBT8DA'
        blocks: [ {
          type: 'rich_text'
          block_id: 'SNqrC'
          elements: [ {
            type: 'rich_text_section'
            elements: [ { type: 'text', text: 'yellow' } ] } ] } ]
        thread_ts: '1578899128.005200'
        user_team: 'TS1T1DGV9'
        source_team: 'TS1T1DGV9'
        channel: 'C1234567'
        event_ts: '1578899141.005500'
        ts: '1578899141.005500'
      await delay 200
      chai.assert.lengthOf share.model.Messages.find().fetch(), 0

    it 'gets mentions from slack', ->
      stubUsers.info.rejects().withArgs(user: 'USCTBT8DA').resolves
        ok: true
        user:
          id: 'USCTBT8DA'
          name: 'torgen'
          real_name: 'Solicitor General'
          profile:
            email: 'torgen@github.com'
      .withArgs(user: 'U123987').resolves
        ok: true
        user:
          id: 'U123987'
          name: 'cjb'
          real_name: 'See Jay Bee'
          profile:
            email: 'cjb@github.com'
      stubConversations.info.rejects().withArgs(channel: 'C999999').resolves
        ok: true
        channel:
          id: 'C999999'
          name: 'chill'
      fakeRtm.emit 'message',
        client_msg_id: '6c09236b-9dea-44b7-8421-b3a572e4f64c'
        suppress_notification: false
        type: 'message'
        text: 'yellow'
        user: 'USCTBT8DA'
        blocks: [ {
          type: 'rich_text'
          block_id: 'SNqrC'
          elements: [ {
            type: 'rich_text_section'
            elements: [
              { type: 'text', text: 'yellow ' },
              { type: 'user', user_id: 'U123987' },
              { type: 'text', text: ' yellow ' }, 
              { type: 'channel', channel_id: 'C999999'} ] } ] } ]
        thread_ts: '1578899128.005200'
        user_team: 'TS1T1DGV9'
        source_team: 'TS1T1DGV9'
        channel: 'C1234567'
        event_ts: '1578899141.005500'
        ts: '1578899141.005500'
      torgen = waitForDocument Meteor.users,
        _id: 'torgen'
      ,
        nickname: 'torgen'
        real_name: 'Solicitor General'
        gravatar: 'torgen@github.com'
      cjb = waitForDocument Meteor.users,
        _id: 'cjb'
      ,
        nickname: 'cjb'
        real_name: 'See Jay Bee'
        gravatar: 'cjb@github.com'
      message = waitForDocument share.model.Messages,
        body: 'yellow cjb yellow #chill'
        room_name: 'general/0'
      ,
        nick: 'torgen'
        slack:
          timestamp: '1578899141.005500'
          from_slack: true
      Promise.all [torgen, cjb, message]

    it 'caches mentions from users table', ->
      Meteor.users.insert
        _id: 'torgen'
        nickname: 'Torgen'
        real_name: 'Solicitor General'
        gravatar: 'torgen@github.com'
        slack_id: 'USCTBT8DA'
      Meteor.users.insert
        _id: 'cjb'
        nickname: 'CJB'
        real_name: 'See Jay Bee'
        gravatar: 'cjb@github.com'
        slack_id: 'U123987'
      stubUsers.info.rejects()
      fakeRtm.emit 'message',
        client_msg_id: '6c09236b-9dea-44b7-8421-b3a572e4f64c'
        suppress_notification: false
        type: 'message'
        text: 'yellow'
        user: 'USCTBT8DA'
        blocks: [ {
          type: 'rich_text'
          block_id: 'SNqrC'
          elements: [ {
            type: 'rich_text_section'
            elements: [
              { type: 'text', text: 'yellow ' },
              { type: 'user', user_id: 'U123987' },
              { type: 'text', text: ' yellow ' },
              { type: 'broadcast', range: 'channel' }, ] } ] } ]
        thread_ts: '1578899128.005200'
        user_team: 'TS1T1DGV9'
        source_team: 'TS1T1DGV9'
        channel: 'C1234567'
        event_ts: '1578899141.005500'
        ts: '1578899141.005500'
      waitForDocument share.model.Messages,
        body: 'yellow CJB yellow @channel'
        room_name: 'general/0'
      ,
        nick: 'torgen'
        slack:
          timestamp: '1578899141.005500'
          from_slack: true

    it 'updates existing users', ->
      Meteor.users.insert
        _id: 'torgen'
        nickname: 'Torgen'
        real_name: 'Solicitor General'
        gravatar: 'torgen@github.com'
        slack_id: 'USCTBT8DA'
      Meteor.users.insert
        _id: 'cjb'
        nickname: 'CJB'
        real_name: 'See Jay Bee'
        gravatar: 'cjb@github.com'
        # note: no slack ID
      stubUsers.info.rejects().withArgs(user: 'U123987').resolves
        ok: true
        user:
          id: 'U123987'
          name: 'cjb'
          real_name: 'Something Else'
          profile:
            email: 'cjb@slack.com'
      fakeRtm.emit 'message',
        client_msg_id: '6c09236b-9dea-44b7-8421-b3a572e4f64c'
        suppress_notification: false
        type: 'message'
        text: 'yellow'
        user: 'USCTBT8DA'
        blocks: [ {
          type: 'rich_text'
          block_id: 'SNqrC'
          elements: [ {
            type: 'rich_text_section'
            elements: [
              { type: 'text', text: 'yellow ' },
              { type: 'user', user_id: 'U123987' },
              { type: 'text', text: ' yellow' }, ] } ] } ]
        thread_ts: '1578899128.005200'
        user_team: 'TS1T1DGV9'
        source_team: 'TS1T1DGV9'
        channel: 'C1234567'
        event_ts: '1578899141.005500'
        ts: '1578899141.005500'
      cjb = waitForDocument Meteor.users,
        _id: 'cjb'
        slack_id: 'U123987'
      ,
        nickname: 'CJB'
        real_name: 'See Jay Bee'
        gravatar: 'cjb@github.com'
      message = waitForDocument share.model.Messages,
        body: 'yellow cjb yellow'
        room_name: 'general/0'
      ,
        nick: 'torgen'
        slack:
          timestamp: '1578899141.005500'
          from_slack: true
      Promise.all [message, cjb]

    it 'parses me messages', ->
      stubUsers.info.rejects().withArgs(user: 'U123987').resolves
        ok: true
        user:
          id: 'U123987'
          name: 'cjb'
          real_name: 'Something Else'
          profile:
            email: 'cjb@slack.com'
      fakeRtm.emit 'message',
        client_msg_id: '6c09236b-9dea-44b7-8421-b3a572e4f64c'
        suppress_notification: false
        type: 'message'
        subtype: 'me_message'
        text: 'waves to <!everyone> but especially <@USCTBT8DA|torgen> and <!channel> too'
        user: 'U123987'
        thread_ts: '1578899128.005200'
        user_team: 'TS1T1DGV9'
        source_team: 'TS1T1DGV9'
        channel: 'C1234567'
        event_ts: '1578899141.005500'
        ts: '1578899141.005500'
      cjb = waitForDocument Meteor.users,
        _id: 'cjb'
        slack_id: 'U123987'
      ,
        nickname: 'cjb'
        real_name: 'Something Else'
        gravatar: 'cjb@slack.com'
      message = waitForDocument share.model.Messages,
        action: true
        nick: 'cjb'
        body: 'waves to @everyone but especially torgen and @channel too'
        room_name: 'general/0'
      ,
        slack:
          timestamp: '1578899141.005500'
          from_slack: true
      Promise.all [message, cjb]

