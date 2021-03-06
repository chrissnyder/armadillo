async = require 'async'
AWS = require 'aws-sdk'
request = require 'request'
url = require 'url'

class Armadillo

  project: ''
  bucket: ''

  host: 'https://api.zooniverse.org'
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

  go: (callback) =>
    async.auto
      getSubjects: @getSubjects
      save: ['getSubjects', @save]
    , (err) =>
      if err?
        console.log "Error updating #{ @project }:", err
      else
        console.log "Updated offline subjects for #{ @project }"

      callback() if callback 

  getSubjects: (callback) =>
    @subjects = []

    # Determine if a project has groups
    options =
      url: url.resolve(@host, "projects/#{ @project }")
      json: true
      strictSSL: false

    request options, (err, res, rawProject) =>

      if rawProject.groups?
        groupOptions = []

        for groupId, groupData of rawProject.groups
          groupOptions.push
            url: url.resolve(@host, "/projects/#{ @project }/groups/#{ groupId }/subjects")
            qs:
              limit: @limit
            strictSSL: false

        async.eachSeries groupOptions, @requestSubjects, (err) =>
          if err
            callback err, null
          else
            callback null, @subjects

      else
        options = 
          url: url.resolve(@host, "/projects/#{ @project }/subjects")
          qs:
            limit: @limit
          strictSSL: false

        @requestSubjects options, callback

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

  requestSubjects: (options, callback) =>
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

  url: =>
    # Attempt to derive the url from the bucket
    if @bucket is 'zooniverse-demo'
      "http://zooniverse-demo.s3-website-us-east-1.amazonaws.com"
    else
      "http://#{ @bucket }"

module.exports = Armadillo
