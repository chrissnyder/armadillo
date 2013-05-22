{EventEmitter} = require 'events'

async = require 'async'
request = require 'request'
phantom = require 'node-phantom'

class Armadillo extends EventEmitter

  # 1. Retrieve current subjects.json
  # 2. Determine if subjects need to be refreshed.
  # 3. If so, eliminate finished subjects and add new ones.
  # 4. Save subjects.json back to bucket

  project: ''
  bucket: ''

  host: 'https://dev.zooniverse.org'
  json: 'offline/subjects.json'

  subjectsToFetch: 0
  offlineJson: ''
  validSubjects: []

  options: null

  constructor: (params = {}) ->
    @[property] = value for own property, value of params when property of @

    # S3
    @s3 = require('knox').createClient
      key: @options.key || process.env.S3_ACCESS_ID
      secret: @options.secret || process.env.S3_SECRET_KEY
      bucket: @bucket

  go: =>
    async.auto
      getHost: @getHost
      getOfflineManifest: @getOfflineManifest
      checkSubjects: ['getHost', 'getOfflineManifest', @checkSubjects]
      refillSubjects: ['checkSubjects', @refillSubjects]
      save: ['refillSubjects', @save]
    , (err) =>
      if err
        console.log 'Error:', err

      process.exit()

  # In general order of calling
  getHost: (callback) =>
    phantom.create (err, ph) =>
      ph.createPage (err, page) =>
        page.open @url(), (err, status) =>
          if err
            ph.exit()
            callback err, null
            return

          page.evaluate ->
            return window.zooniverse.Api.current.proxyFrame.host
          , (err, @host) ->
            ph.exit()

            if err
              callback err, null
              return

            callback null, @host

  getOfflineManifest: (callback) =>
    @s3.getFile @json, (err, res) =>
      if err
        callback err, null
        return

      res.on 'data', (chunk) =>
        @offlineJson += chunk

      res.on 'end', =>
        try
          @offlineJson = JSON.parse @offlineJson
        catch e
          # JSON was malformed in subjects.json.
          @subjectsToFetch = 3
          @offlineJson = []

        callback null, @offlineJson

  checkSubjects: (callback) =>
    @offlineZooIds = []

    for subject in @offlineJson
      unless "zooniverse_id" in subject
        @subjectsToFetch += 1

      else
        @offlineZooIds.push subject.zooniverse_id

    options =
      body: { subject_ids: @offlineZooIds }
      url: "#{ @host }/projects/#{ @project }/subjects/batch"
      method: 'POST'
      json: true
      strictSSL: false

    request options, (err, res, fetchedSubjects) =>
      if err
        callback err, null
        return

      for subject in fetchedSubjects

        if subject.state is 'active'
          @validSubjects.push subject

        else
          @subjectsToFetch += 1

      callback null, fetchedSubjects

  refillSubjects: (callback) =>
    options = 
      url: "#{ @host }/projects/#{ @project }/subjects"
      qs:
        limit: Math.min @subjectsToFetch, 3
      strictSSL: false

    request options, (err, res, rawSubjects) =>
      if err
        callback err, null
        return

      for subject in JSON.parse(rawSubjects)
        @validSubjects.push subject

      callback null, @validSubjects

  save: (callback) =>
    buffer = new Buffer JSON.stringify @validSubjects

    headers =
      'x-amz-acl': 'public-read'
      'Content-Type': 'application/json'

    @s3.putBuffer buffer, @json, headers, (err, res) ->
      if err
        callback err, null
        return

      callback null, res

  url: =>
    # Attempt to derive the url from the bucket
    if @bucket is 'zooniverse-demo'
      "http://zooniverse-demo.s3-website-us-east-1.amazonaws.com"
    else
      "http://#{ @bucket }"

module.exports = Armadillo