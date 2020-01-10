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
  webClient = null

  beforeEach ->
    fakeRtm = new EventEmitter
    fakeRtm.sendMessage = ->
    rtmMock = sinon.mock fakeRtm
    fakeRtm.webClient = new WebClient
    webClient = sinon.mock fakeRtm.webClient

  afterEach ->
    sinon.verifyAndRestore()

  handle = null
  afterEach ->
    handle?.stop()

  it 'looks up #channel', ->
    webClient.expects('apiCall').once().withArgs('users.conversations', {}).resolves
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
    webClient.expects('apiCall').once().withArgs('users.conversations', {}).resolves
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
    webClient.expects('apiCall').twice().onFirstCall().resolves
      ok: true
      channels: [
        {
          id: 'C0123456'
          name_normalized: 'general'
        }
      ]
      response_metadata: {next_cursor: 'abcde'}
    .onSecondCall().resolves
      ok: true
      channels: [
        {
          id: 'C1234567'
          name_normalized: 'frumious'
        }
      ]
      response_metadata: {next_cursor: ''}
    handle = install fakeRtm, '#frumious'

  describe 'on message', ->
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
      

