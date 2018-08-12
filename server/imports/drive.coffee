'use strict'

# Drive folder settings
ROOT_FOLDER_NAME = Meteor.settings.folder or 'MIT Mystery Hunt 2014'
CODEX_ACCOUNT = 'zouchenuttall@gmail.com'
CODEX_HUMAN_NAME = 'Zouche Nuttall'
WORKSHEET_NAME = (name) -> "Worksheet: #{name}"

# Constants
GDRIVE_FOLDER_MIME_TYPE = 'application/vnd.google-apps.folder'
GDRIVE_SPREADSHEET_MIME_TYPE = 'application/vnd.google-apps.spreadsheet'
XLSX_MIME_TYPE = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
MAX_RESULTS = 200
SPREADSHEET_TEMPLATE = Assets.getBinary 'spreadsheet-template.xlsx'

quote = (str) -> "'#{str.replace(/([\'\\])/g, '\\$1')}'"

samePerm = (p, pp) ->
  (p.withLink or false) is (pp.withLink or false) and \
  p.role is pp.role and \
  p.type is pp.type and \
  if p.type is 'anyone'
    true
  else if ('value' of p) and ('value' of pp)
    (p.value is pp.value)
  else # hack! google doesn't return the full email address in the permission
    (p.type is 'user' and p.value is CODEX_ACCOUNT and pp.name is CODEX_HUMAN_NAME)

userRateExceeded = (error) ->
  return false unless error.code == 403
  for subError in error.errors
    if subError.domain is 'usageLimits' and subError.reason is 'userRateLimitExceeded'
      return true
  return false

delays = [100, 250, 500, 1000, 2000, 5000, 10000]

afterDelay = (ix, base, name, params, callback) ->
  try
    r = Gapi.exec base, name, params 
    callback null, r
  catch error
    if ix >= delays.length or not userRateExceeded(error)
      callback error, null
      return
    console.warn "Rate limited for #{name}; Will retry after #{delays[ix]}ms"
    later = ->
      afterDelay ix+1, base, name, params, callback
    Meteor.setTimeout later, delays[ix]
    
apiThrottle = Meteor.wrapAsync (base, name, params, callback) ->
  afterDelay 0, base, name, params, callback

ensurePermissions = (drive, id) ->
  # give permissions to both anyone with link and to the primary
  # service acount.  the service account must remain the owner in
  # order to be able to rename the folder
  perms = [
    # edit permissions to codex account
    withLink: false
    role: 'writer'
    type: 'user'
    value: CODEX_ACCOUNT
  ,
    # edit permissions for anyone with link
    withLink: true
    role: 'writer'
    type: 'anyone'
  ]
  resp = apiThrottle drive.permissions, 'list', fileId: id
  perms.forEach (p) ->
    # does this permission already exist?
    exists = resp.items.some (pp) -> samePerm p, pp
    unless exists
      apiThrottle drive.permissions, 'insert',
        fileId: id
        resource: p
  'ok'

spreadsheetSettings =
  titleFunc: WORKSHEET_NAME
  driveMimeType: GDRIVE_SPREADSHEET_MIME_TYPE
  uploadMimeType: XLSX_MIME_TYPE
  uploadTemplate: SPREADSHEET_TEMPLATE
  
ensure = (drive, name, folder, settings) ->
  doc = apiThrottle drive.children, 'list',
    folderId: folder.id
    q: "title=#{quote settings.titleFunc name} and mimeType=#{quote settings.driveMimeType}"
    maxResults: 1
  .items[0]
  unless doc?
    doc =
      title: settings.titleFunc name
      mimeType: settings.uploadMimeType
      parents: [id: folder.id]
    doc = apiThrottle drive.files, 'insert',
      convert: true
      body: doc
      resource: doc
      media:
        mimeType: settings.uploadMimeType
        body: settings.uploadTemplate
  ensurePermissions drive, doc.id
  return doc

ensureFolder = (drive, name, parent) ->
  # check to see if the folder already exists
  resp = apiThrottle drive.children, 'list',
    folderId: parent or 'root'
    q: "title=#{quote name}"
    maxResults: 1
  if resp.items.length > 0
    resource = resp.items[0]
  else
    # create the folder
    resource =
      title: name
      mimeType: GDRIVE_FOLDER_MIME_TYPE
    resource.parents = [id: parent] if parent
    resource = apiThrottle drive.files, 'insert',
      resource: resource
  # give the new folder the right permissions
  ensurePermissions drive, resource.id
  resource

rmrfFolder = (drive, id) ->
  resp = {}
  loop
    # delete subfolders
    resp = apiThrottle drive.children, 'list',
      folderId: id
      q: "mimeType=#{quote GDRIVE_FOLDER_MIME_TYPE}"
      maxResults: MAX_RESULTS
      pageToken: resp.nextPageToken
    resp.items.forEach (item) ->
      rmrfFolder item.id
    break unless resp.nextPageToken?
  loop
    # delete non-folder stuff
    resp = apiThrottle drive.children, 'list',
      folderId: id
      q: "mimeType!=#{quote GDRIVE_FOLDER_MIME_TYPE}"
      maxResults: MAX_RESULTS
      pageToken: resp.nextPageToken
    resp.items.forEach (item) ->
      apiThrottle drive.files, 'delete', fileId: item.id
    break unless resp.nextPageToken?
  # folder empty; delete the folder and we're done
  apiThrottle drive.files, 'delete', fileId: id
  'ok'

export class Drive
  constructor: (@drive) ->
    @rootFolder = (ensureFolder @drive, ROOT_FOLDER_NAME).id
    @ringhuntersFolder = (ensureFolder @drive, 'Ringhunters Uploads', @rootFolder).id
  
  createPuzzle: (name) ->
    folder = ensureFolder @drive, name, @rootFolder
    # is the spreadsheet already there?
    spreadsheet = ensure @drive, name, folder, spreadsheetSettings
    return {
      id: folder.id
      spreadId: spreadsheet.id
    }

  findPuzzle: (name) ->
    resp = apiThrottle @drive.children, 'list',
      folderId: @rootFolder
      q: "title=#{quote name} and mimeType=#{quote GDRIVE_FOLDER_MIME_TYPE}"
      maxResults: 1
    folder = resp.items[0]
    return null unless folder?
    # TODO: batch these requests together.
    # look for spreadsheet
    spread = apiThrottle @drive.children, 'list',
      folderId: folder.id
      q: "title=#{quote WORKSHEET_NAME name}"
      maxResults: 1
    return {
      id: folder.id
      spreadId: spread.items[0]?.id
    }

  listPuzzles: ->
    results = []
    resp = {}
    loop
      resp = apiThrottle @drive.children, 'list',
        folderId: @rootFolder
        q: "mimeType=#{quote GDRIVE_FOLDER_MIME_TYPE}"
        maxResults: MAX_RESULTS
        pageToken: resp.nextPageToken
      results.push resp.items...
      break unless resp.nextPageToken?
    results

  renamePuzzle: (name, id, spreadId) ->
    apiThrottle @drive.files, 'patch',
      fileId: id
      resource:
        title: name
    if spreadId?
      apiThrottle @drive.files, 'patch',
        fileId: spreadId
        resource:
          title: WORKSHEET_NAME name
    'ok'

  deletePuzzle: (id) -> rmrfFolder @drive, id

  # purge `rootFolder` and everything in it
  purge: -> rmrfFolder @drive, rootFolder

# generate functions
skip = (type) -> -> console.warn "Skipping Google Drive operation:", type

export class FailDrive
  createPuzzle: skip 'createPuzzle'
  findPuzzle: skip 'findPuzzle'
  listPuzzles: skip 'listPuzzles'
  renamePuzzle: skip 'renamePuzzle'
  deletePuzzle: skip 'deletePuzzle'
  purge: skip 'purge'
