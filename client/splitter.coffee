# cscott's very simple splitter widget
'use strict'

import { reactiveLocalStorage } from './imports/storage.coffee'

class Dimension
  constructor: (@targetClass, @posProperty, @splitterProperty) ->
    @dragging = new ReactiveVar false
    @size = new ReactiveVar 300
  get: () -> Math.max @size.get(), 0
  set: (size) ->
    if not size?
      size = 300
    @size.set size
    +size
  handleEvent: (event, template) ->
    event.preventDefault() # don't highlight text, etc.
    pane = $(event.currentTarget).closest(@targetClass)
    @dragging.set true
    initialPos = event[@posProperty]
    initialSize = @get()
    mouseMove = (mmevt) =>
      newSize = initialSize - (mmevt[@posProperty] - initialPos)
      @set newSize
    mouseUp = (muevt) =>
      pane.removeClass('active')
      $(document).unbind('mousemove', mouseMove).unbind('mouseup', mouseUp)
      reactiveLocalStorage.setItem "splitter.#{@splitterProperty}", @size.get()
      @dragging.set false
    pane.addClass('active')
    $(document).bind('mousemove', mouseMove).bind('mouseup', mouseUp)


Splitter = share.Splitter =
  vsize: new Dimension '.bb--right-content', 'pageY', 'vsize'
  hsize: new Dimension  '.bb-splitter', 'pageX', 'hsize'
  handleEvent: (event, template) ->
    console.log event.currentTarget unless Meteor.isProduction
    if $(event.currentTarget).closest('.bb-right-content').length
      @vsize.handleEvent event, template
    else
      @hsize.handleEvent event, template
 
['hsize', 'vsize'].forEach (dim) ->
  Tracker.autorun ->
    x = Splitter[dim]
    return if x.dragging.get()
    console.log "about to set #{dim}"
    val = reactiveLocalStorage.getItem "splitter.#{dim}"
    return unless val?
    x.set val

Template.horizontal_splitter.helpers
  hsize: -> Splitter.hsize.get()

Template.horizontal_splitter.events
  'mousedown .bb-splitter-handle': (e,t) -> Splitter.handleEvent(e,t)

Template.horizontal_splitter.onCreated ->
  $('html').addClass('fullHeight')

Template.horizontal_splitter.onRendered ->
  $('html').addClass('fullHeight')

Template.horizontal_splitter.onDestroyed ->
  $('html').removeClass('fullHeight')

Template.vertical_splitter.helpers
  vsize: -> share.Splitter.vsize.get()
  vsizePlusHandle: -> +share.Splitter.vsize.get() + 6
