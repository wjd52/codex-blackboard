'use strict'

import { Drive, FailDrive } from './imports/drive.coffee'

# helper functions to perform Google Drive operations

# Credentials
KEY = Meteor.settings.key or Assets.getBinary 'drive-key.pem.crypt'
if Meteor.settings.password?
  # Decrypt the JWT authentication key synchronously at startup
  KEY = Gapi.decrypt KEY, Meteor.settings.password
EMAIL = Meteor.settings.email or '571639156428@developer.gserviceaccount.com'
SCOPES = ['https://www.googleapis.com/auth/drive']

# Intialize APIs and load rootFolder
do ->
  try
    unless /^-----BEGIN RSA PRIVATE KEY-----/.test(KEY)
      throw "INVALID GOOGLE DRIVE KEY OR PASSWORD"
    jwt = new Gapi.apis.auth.JWT(EMAIL, null, KEY, SCOPES)
    jwt.credentials = Gapi.authorize(jwt);
    # record the API and auth info
    api = Gapi.apis.drive('v2')
    Gapi.registerAuth jwt
    share.drive = new Drive api
    console.log "Google Drive authorized and activated"
  catch error
    console.warn "Error trying to retrieve drive API:", error.__proto__
    console.warn "Google Drive integration disabled."
    share.drive = new FailDrive
