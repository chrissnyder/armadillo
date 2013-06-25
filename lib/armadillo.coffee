async = require 'async'
AWS = require 'aws-sdk'
phantom = require 'node-phantom'
request = require 'request'
url = require 'url'

class Armadillo

  project: ''
  bucket: ''

  host: 'https://dev.zooniverse.org'
  json: 'offline/subjects.json'

  limit: 3
  subjects: []

  options: {}

  constructor: (params = {}) ->
    @[property] = value for own property, value of params when property of @

    # S3
    @s3 ?= new AWS.S3
      accessKeyId: @options.key || process.env.AMAZON_ACCESS_KEY_ID
      secretAccessKey: @options.secret || process.env.AMAZON_SECRET_ACCESS_KEY
      region: @options.region || 'us-east-1'

  go: =>
    async.auto
      getHost: @getHost
      getSubjects: ['getHost', @getSubjects]
      save: ['getSubjects', @save]
    , (err) =>
      if err? then console.log 'Error:', err

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
          , (err, @host) =>
            ph.exit()

            if err
              callback err, null
              return
            else unless @host?
              callback 'Failed to retrieve API host from page.', null
              return
            else unless url.parse @host
              callback 'Host retrieved is invalid URI', null

            callback null, @host

  getSubjects: (callback) =>
    options = 
      url: url.resolve(@host, "/projects/#{ @project }/subjects")
      qs:
        limit: @limit
      strictSSL: false

    request options, (err, res, rawSubjects) =>
      if err
        callback err, null
        return
      else unless rawSubjects.length
        callback 'No active subjects.', null
        return

      for subject in JSON.parse(rawSubjects)
        @subjects.push subject

      callback null, @subjects

  save: (callback) =>
    buffer = new Buffer JSON.stringify @subjects

    @s3.putObject
      Bucket: @bucket
      Key: @json
      ACL: 'public-read'
      Body: buffer
      ContentType: 'application/json'
      (err, res) ->
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
