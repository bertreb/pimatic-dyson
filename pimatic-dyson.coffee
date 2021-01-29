module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  M = env.matcher
  _ = require('lodash')
  purelink = require('dyson-purelink')

  class DysonPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>

      pluginConfigDef = require './pimatic-dyson-config-schema'

      @deviceConfigDef = require("./device-config-schema")

      @email = @config.email # "email@domain.com";
      @password = @config.password #"a1b2c3d4";
      @country = @config.country

      @polltime = @config.polltime ? 60000

      @purelink = new purelink(@email, @password, @country)
      @purelinkReady = true

      env.logger.debug "@purelink: " + JSON.stringify(@purelink,null,2)

      @framework.deviceManager.registerDeviceClass('DysonDevice', {
        configDef: @deviceConfigDef.DysonDevice,
        createCallback: (config, lastState) => new DysonDevice(config, lastState, @, @client, @framework)
      })

      @framework.ruleManager.addActionProvider(new DysonActionProvider(@framework))

      @framework.deviceManager.on('discover', (eventData) =>
        @framework.deviceManager.discoverMessage 'pimatic-dyson', 'Searching for new devices'

        if @purelinkReady and _.size(@purelink.devices) > 0
          @purelink.getDevices()
          .then (devices)=>
            for device in devices
              deviceConfig = device._deviceInfo
              #env.logger.debug "DeviceConfig: " + JSON.stringify(deviceConfig,null,2)
              _did = "dyson-" + (deviceConfig.Name).split(' ').join("_").toLowerCase()
              if _.find(@framework.deviceManager.devicesConfig,(d) => (d.id).indexOf(_did)>=0)
                env.logger.info "Device '" + _did + "' already in config"
              else
                config =
                  id: _did
                  name: deviceConfig.Name
                  class: "DysonDevice"
                  serial: deviceConfig.Serial
                  type: deviceConfig.ProductType
                  product: @getFriendlyName(deviceConfig.ProductType)
                  version: deviceConfig.Version
                @framework.deviceManager.discoveredDevice( "Dyson", config.name, config)
          .catch (err)=>
            env.logger.error "Error discovery @purelink.getDevices(): " + err
      )

    getFriendlyName: (type)->
      friendlyNames =
        358: 'Dyson Pure Humidify+Cool'
        438: 'Dyson Pure Cool Tower'
        455: 'Dyson Pure Hot+Cool Link'
        469: 'Dyson Pure Cool Link Desk'
        475: 'Dyson Pure Cool Link Tower'
        520: 'Dyson Pure Cool Desk'
        527: 'Dyson Pure Hot+Cool'
      return friendlyNames[type] ? type

  class DysonDevice extends env.devices.Device

    attributes:
      deviceFound:
        description: "Status if local device is found"
        type: "boolean"
        acronym: "Device"
        labels: ["found","not found"]
      deviceStatus:
        description: "Status of device"
        type: "boolean"
        acronym: "Device"
        labels: ["on","off"]
      temperature:
        description: "Temperature"
        type: "number"
        unit: "°C"
        acronym: "T"
      airQuality:
        description: "Air Quality"
        type: "number"
        acronym: "AQ"
      relativeHumidity:
        description: "Relative Humidity"
        type: "number"
        unit: "%"
        acronym: "RHum"
      fanStatus:
        description: "Fan status if fan is on or off"
        type: "boolean"
        acronym: "Fan"
        labels: ["on","off"]
      fanSpeed:
        description: "Fan speed"
        type: "number"
        unit: "rpm"
        acronym: "Speed"
      rotationStatus:
        description: "Rotation status"
        type: "boolean"
        acronym: "Rotation"
        labels: ["on","off"]
      autoOnStatus:
        description: "The AutoOn status"
        type: "boolean"
        acronym: "Auto"
        labels: ["on","off"]


    constructor: (config, lastState, @plugin, client, @framework) ->
      @config = config
      @id = @config.id
      @name = @config.name

      @purelinkDevice = null
      @purelink = @plugin.purelink

      @pollTime = @plugin.polltime
      @deviceReady = false

      @_deviceFound = laststate?.deviceFound?.value ? false
      @_deviceStatus = laststate?.deviceStatus?.value ? false
      @_temperature = laststate?.temperature?.value ? 0
      @_airQuality = laststate?.airQuality?.value ? 0
      @_relativeHumidity = laststate?.relativeHumidity?.value ? 0
      @_fanStatus = laststate?.fanStatus?.value ? false
      @_fanSpeed = laststate?.fanSpeed?.value ? 0
      @_rotationStatus = laststate?.rotationStatus?.value ? false
      @_autoOnStatus = laststate?.autoOnStatus?.value ? false

      @framework.variableManager.waitForInit()
      .then ()=>
        #env.logger.debug "(re)starting DysonDevice #{@id}: plugin.purelink: " + @purelink
        env.logger.debug "============>  @purelink?.getDevices? size: " + _.size(@purelink._devices)
        #return
        if _.size(@purelink._devices) > 0 # devcies registered in the cloud
          @purelink.getDevices()
          .then (devices)=>
            #deviceList = _.map(devices,(d)=> "dyson-"+d._deviceInfo.Name.toLowerCase())
            env.logger.debug "Devices found in the cloud: " + _.size(devices) # deviceList
            _device = _.find(devices, (d)=> d._deviceInfo.Serial is @config.serial)
            if _device?
              if _.size(@plugin.purelink._networkDevices) > 0
                @purelinkDevice = _device
                @deviceReady = true
                @setDeviceFound(true)
                @startStatusPolling()
                env.logger.debug "Device '#{@id}' found locally, status polling started"
              else
                env.logger.debug "Device '#{@id}' not found locally"
                @deviceReady = false
                @setDeviceFound(false)
            else
              env.logger.debug "Device '#{@id}' not registered in the cloud "
              @setDeviceFound(false)
              @deviceReady = false
          .catch (err)=>
            env.logger.error "Error after init @purelink.getDevices(): " + err


      @startStatusPolling = () =>
        #env.logger.debug "@startStatusPolling: " + @plugin.clientReady
        if @deviceReady and @purelinkDevice?
          @purelinkDevice.getTemperature()
          .then (temperature)=>
            if temperature?
              @_temperature = temperature
              @emit 'temperature', temperature
            return @purelinkDevice.getAirQuality()
          .then (airQuality)=>
            if airQuality?
              @_airQuality = airQuality
              @emit 'airQuality', airQuality
            return @purelinkDevice.getRelativeHumidity()
          .then (relativeHumidity)=>
            if relativeHumidity?
              @_relativeHumidity = relativeHumidity
              @emit 'relativeHumidity', relativeHumidity
            return @purelinkDevice.getFanStatus()
          .then (fanStatus)=>
            if fanStatus?
              @setFanStatus(fanStatus)
            return @purelinkDevice.getFanSpeed()
          .then (fanSpeed)=>
            if fanSpeed?
              @setFanSpeed(fanspeed)
            return @purelinkDevice.getRotationStatus()
          .then (rotation)=>
            if rotation?
              @setRotationStatus(rotation)
            return @purelinkDevice.getAutoOnStatus()
          .then (autoOnStatus)=>
            if autoOnStatus?
              @setAutoOnStatus(autoOnStatus)
          .catch (e) =>
            env.logger.debug "GetStatus error: " + JSON.stringify(e,null,2)
          env.logger.debug "All status info received"
          @statusTimer = setTimeout(@startStatusPolling, @pollTime)
          env.logger.debug "Next poll in " + @pollTime + " ms"
        else
          env.logger.info "Device not available, no more polling, restart device or plugin"


      super()

    findDevice: ()=>
      result =
        device: null
        cloud: false
        local: false
      # check if device exists in the cloud
      _device = _.find(@purelink._devices, (d)=> d._deviceInfo.Serial is @config.serial)
      #check if device exists and if device is locally found via bonjour (see dyson-purelink)
      if _device?
        result.device = _device
        result.cloud = true
        if _.size(@plugin.purelink._networkDevices) > 0
          result.local = true
      return result

    execute: (command, options) =>
      return new Promise((resolve,reject) =>

        env.logger.debug "Execute command: " + command + ", options: " + JSON.stringify(options,null,2)

        unless @purelinkReady
          reject("Device not ready")

        switch command
          when "on"
            env.logger.debug "Turn dyson on "
            @purelinkDevice.turnOn()
            .then (resp)=>
              env.logger.debug "Dyson turned on"
              @setDeviceStatus(off)
              resolve()
            .catch (err) =>
              env.logger.debug "Error turning on: " + JSON.stringify(err,null,2)
              reject()
          when "off"
            env.logger.debug "Turn dyson off "
            @purelinkDevice.turnOff()
            .then (resp)=>
              env.logger.debug "Dyson turned off"
              @setDeviceStatus(on)
              resolve()
            .catch (err) =>
              env.logger.debug "Error turning off: " + JSON.stringify(err,null,2)
              reject()
          when "auto"
            env.logger.debug "Turn dyson auto " + options.auto
            @purelinkDevice.setAuto(options.auto)
            .then (resp)=>
              env.logger.debug "Dyson auto: " + option.auto
              @setAutoOnStatus(option.auto)
              resolve()
            .catch (err) =>
              env.logger.debug "Error turning off: " + JSON.stringify(err,null,2)
              reject()
          when "fan"
            env.logger.debug "Turn dyson fan: " + options.fan
            @purelinkDevice.setFan(options.fan)
            .then ()=>
              env.logger.debug "Dyson fan: " + options.fan
              @setFanStatus(options.fan)
              resolve()
            .catch (err) =>
              env.logger.debug "Error fan: " + JSON.stringify(err,null,2)
              reject()
          when "speed"
            env.logger.debug "Turn dyson speed on: " + options.speed
            @purelinkDevice.setFanSpeed(options.speed)
            .then ()=>
              env.logger.debug "Dyson speed turned on"
              @setFanSpeed(options.speed)
              resolve()
            .catch (err) =>
              env.logger.debug "Error fanspeed: " + JSON.stringify(err,null,2)
              reject()
          when "rotation"
            env.logger.debug "Turn dyson rotation: " + options.rotation
            @purelinkDevice.setRotation(options.rotation)
            .then ()=>
              env.logger.debug "Dyson rotation turned  " + options.rotation
              @setRotationStatus(options.rotation)
              resolve()
            .catch (err) =>
              env.logger.debug "Error turning rotation:" + JSON.stringify(err,null,2)
              reject()
          else
            env.logger.debug "Unknown command " + command
            reject()
        resolve()
      )

    getDeviceFound: -> Promise.resolve(@_deviceFound)
    getDeviceStatus: -> Promise.resolve(@_deviceStatus)
    getTemperature: -> Promise.resolve(@_temperature)
    getAirQuality: -> Promise.resolve(@_airQuality)
    getRelativeHumidity: -> Promise.resolve(@_relativeHumidity)
    getFanStatus: -> Promise.resolve(@_fanStatus)
    getFanSpeed: -> Promise.resolve(@_fanSpeed)
    getRotationStatus: -> Promise.resolve(@_rotationStatus)
    getAutoOnStatus: -> Promise.resolve(@_autoOnStatus)


    setDeviceStatus: (_status) =>
      @_engine = Boolean _status
      @emit 'deviceStatus', Boolean _status

    setDeviceFound: (_status) =>
      @_status = Boolean _status
      @emit 'deviceFound', Boolean _status

    setFanSpeed: (_status) =>
      @_fanSpeed = Number _status
      @emit 'fanSpeed', Number _status

    setFanStatus: (_status) =>
      @_fanStatus = Number _status
      @emit 'fanStatus', Number _status

    setRotationStatus: (_status) =>
      @_rotationStatus = Boolean _status
      @emit 'rotationStatus', Boolean _status

    setAutoOnStatus: (_status) =>
      @_autoOnStatus = Boolean _status
      @emit 'autoOnStatus', Boolean _status


    destroy:() =>
      clearTimeout(@statusTimer) if @statusTimer?
      super()

  class DysonActionProvider extends env.actions.ActionProvider

    constructor: (@framework) ->

    parseAction: (input, context) =>

      dysonDevice = null
      @options =
        fan: false
        speed: 0
        speedVar: null
        auto: false
        rotation: false

      dysonDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => device.config.class == "DysonDevice"
      ).value()

      setCommand = (command) =>
        @command = command

      speed = (m,tokens) =>
        unless Number tokens <=100 and Number tokens >= 0
          context?.addError("Speed must be between 0 and 100")
          return
        setCommand("speed")
        @options.speed = Number tokens
      speedVar = (m,tokens) =>
        setCommand("speed")
        @options.speedVar = tokens

      optionsString = (m,tokens) =>
        unless tokens?
          context?.addError("No variable")
          return
        @options = tokens
        setCommand("start")

      m = M(input, context)
        .match('dyson ')
        .matchDevice(dysonDevices, (m, d) ->
          # Already had a match with another device?
          if dysonDevice? and dysonDevices.id isnt d.id
            context?.addError(""""#{input.trim()}" is ambiguous.""")
            return
          dysonDevice = d
        )
        .or([
          ((m) =>
            return m.match(' on', (m) =>
              setCommand('on')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' off', (m) =>
              setCommand('off')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' fan ')
              .or([
                ((m) =>
                  @options.fan = true
                  setCommand("fan")
                  return m.match('on')
                ),
                ((m) =>
                  @options.fan = false
                  setCommand("fan")
                  return m.match('off')
                ),
              ])
          ),
          ((m) =>
            return m.match(' rotation ')
              .or([
                ((m) =>
                  @options.fan = true
                  setCommand("rotation")
                  return m.match('on')
                ),
                ((m) =>
                  @options.fan = false
                  setCommand("rotation")
                  return m.match('off')
                ),
              ])
          ),
          ((m) =>
            return m.match(' speed ')
              .or([
                ((m) =>
                  m.matchNumber(speed)
                ),
                ((m) =>
                  m.matchVariable(speedVar)
                ),
              ])
          ),
          ((m) =>
            return m.match(' auto ')
              .or([
                ((m) =>
                  @options.fan = true
                  setCommand("auto")
                  return m.match('on')
                ),
                ((m) =>
                  @options.fan = false
                  setCommand("auto")
                  return m.match('off')
                ),
              ])
          )
        ])

      match = m.getFullMatch()
      if match? #m.hadMatch()
        env.logger.debug "Rule matched: '", match, "' and passed to Action handler"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new DysonActionHandler(@framework, dysonDevice, @command, @options)
        }
      else
        return null


  class DysonActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @dysonDevice, @command, @options) ->

    executeAction: (simulate) =>
      if simulate
        return __("would have Dyson pure action \"%s\"", "")
      else

        if @options.speedVar?
          _var = @options.speedVar.slice(1) if @options.speedVar.indexOf('$') >= 0
          _optionsSpeed = @framework.variableManager.getVariableValue(_var)
          unless _optionsSpeed?
            return __("\"%s\" Rule not executed, #{_var} is not a valid variable", "")
          if _optionsSpeed > 100 then _optionsSpeed = 100
          if _optionsSpeed < 0 then _optionsSpeed = 0
          @options.speed = _optionsSpeed

        @dysonDevice.execute(@command, @options)
        .then(()=>
          return __("\"%s\" Rule executed", @command)
        ).catch((err)=>
          return __("\"%s\" Rule not executed", "")
        )

  dysonPlugin = new DysonPlugin
  return dysonPlugin
