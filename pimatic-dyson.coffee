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

      @client = null
      @clientReady = false

      @devices = []

      @framework.on 'after init', ()=>
        @purelink = new purelink(@email, @password, @country)
        @clientReady = true
        @emit "clientReady"

      @framework.deviceManager.registerDeviceClass('DysonDevice', {
        configDef: @deviceConfigDef.DysonDevice,
        createCallback: (config, lastState) => new DysonDevice(config, lastState, @, @client, @framework)
      })

      #@framework.ruleManager.addActionProvider(new DysonActionProvider(@framework))

      @framework.deviceManager.on('discover', (eventData) =>
        @framework.deviceManager.discoverMessage 'pimatic-dyson', 'Searching for new devices'

        if @clientReady
          @purelink.getDevices()
          .then((devices) =>
            for device in devices
              #env.logger.info "Device: " + JSON.stringify(device,null,2)
              deviceConfig = device._deviceInfo
              env.logger.info "DeviceConfig: " + JSON.stringify(deviceConfig,null,2)
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
          ).catch((e) =>
            env.logger.error 'Error in getDevices: ' +  JSON.stringify(e,null,2)
          )
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
      status:
        description: "Status is dyson is switched on of off"
        type: "boolean"
        acronym: "Status"
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

      @pollTime = @plugin.polltime
      @deviceReady = false

      @_status = laststate?.status?.value ? false
      @_temperature = laststate?.temperature?.value ? 0
      @_airQuality = laststate?.airQuality?.value ? 0
      @_relativeHumidity = laststate?.relativeHumidity?.value ? 0
      @_fanStatus = laststate?.fanStatus?.value ? false
      @_fanSpeed = laststate?.fanSpeed?.value ? 0
      @_rotationStatus = laststate?.rotationStatus?.value ? false
      @_autoOnStatus = laststate?.autoOnStatus?.value ? false

      @plugin.on 'clientReady', @clientListener = () =>
        _device = @getDevice()
        if _device?
          @purelinkDevice = _device
          @deviceReady = true
          @getStatus()
        else
          env.logger.debug "Device not available "
          @setStatus(off)

      @framework.variableManager.waitForInit()
      .then ()=>
        if @plugin.clientReady and not @statusTimer? and @purelinkDevice?
          _device = @getDevice()
          if _device?
            @purelinkDevice = _device
            @deviceReady = true
            @getStatus()
          else
            env.logger.debug "Device found in the cloud but not local available "
            @setStatus(off)
        else
          env.logger.debug "Device not available "
          @setStatus(off)

      @getStatus = () =>
        #env.logger.debug "@getStatus: " + @plugin.clientReady
        if @plugin.clientReady and @purelinkDevice?
          env.logger.debug "requesting status " + JSON.stringify(@plugin.devices[0],null,2)
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
            return @purelinkDevice.getAutoOnStatus()
          .then (autoOnStatus)=>
            if autoOnStatus?
              @setAutoOnStatus(autoOnStatus)
          .finally ()=>
            env.logger.debug "All status info received"
          .catch (e) =>
            env.logger.debug "getStatus error: " + JSON.stringify(e,null,2)
          @statusTimer = setTimeout(@getStatus, @pollTime)
          env.logger.debug "Next poll in " + @pollTime + " ms"

      super()

    getDevice: ()=>
      if @purelinkDevice?.getDevices?
        @purelinkDevice.getDevices()
        .then (devices)=>
          _device = _.find(devices, (d)=> d._deviceInfo.Serial is config.serial)
          if _device? and _.size(@purelinkDevice._devices) > 0
            return _device
      return null


    execute: (command, options) =>
      return new Promise((resolve,reject) =>

        switch command
          when "on"
            env.logger.debug "Turn dyson on "
            @purelinkDevice.turnOn()
            .then (resp)=>
              env.logger.debug "Dyson turned on"
              @setStatus(on)
              resolve()
            .catch (err) =>
              env.logger.debug "Error turning on: " + JSON.stringify(err,null,2)
              reject()
          when "off"
            env.logger.debug "Turn dyson off "
            @purelinkDevice.turnOff()
            .then (resp)=>
              env.logger.debug "Dyson turned off"
              @setStatus(off)
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
          when "fanspeed"
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
            @purelinkDevice.setFanSpeed(options.rotation)
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

    getStatus: -> Promise.resolve(@_status)
    getTemperature: -> Promise.resolve(@_temperature)
    getAirQuality: -> Promise.resolve(@_airQuality)
    getRelativeHumidity: -> Promise.resolve(@_relativeHumidity)
    getFanStatus: -> Promise.resolve(@_fanStatus)
    getFanSpeed: -> Promise.resolve(@_fanSpeed)
    getRotationStatus: -> Promise.resolve(@_rotationStatus)
    getAutoOnStatus: -> Promise.resolve(@_autoOnStatus)


    setStatus: (_status) =>
      @_status = Boolean _status
      @emit 'status', Boolean _status

    setEngine: (_status) =>
      @_engine = Boolean _status
      @emit 'engine', Boolean _status

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
      @removeListener('clientReady', @clientListener)
      super()

  class DysonActionProvider extends env.actions.ActionProvider

    constructor: (@framework) ->

    parseAction: (input, context) =>

      dysonDevice = null
      @options = null
  
      dysonDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => device.config.class == "DysonDevice"
      ).value()

      setCommand = (command) =>
        @command = command

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
            return m.match(' start ')
              .matchVariable(optionsString)
          ),
          ((m) =>
            return m.match(' stop', (m) =>
              setCommand('stop')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' lock', (m) =>
              setCommand('lock')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' unlock', (m) =>
              setCommand('unlock')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' startCharge', (m) =>
              setCommand('startCharge')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' stopCharge', (m) =>
              setCommand('stopCharge')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' refresh', (m) =>
              setCommand('refresh')
              match = m.getFullMatch()
            )
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
        return __("would have cleaned \"%s\"", "")
      else

        if @options?
          _var = @options.slice(1) if @options.indexOf('$') >= 0
          _options = @framework.variableManager.getVariableValue(_var)
          unless _options?
            return __("\"%s\" Rule not executed, #{_var} is not a valid variable", "")
        else
          _options = null

        @dysonDevice.execute(@command, _options)
        .then(()=>
          return __("\"%s\" Rule executed", @command)
        ).catch((err)=>
          return __("\"%s\" Rule not executed", "")
        )

  dysonPlugin = new DysonPlugin
  return dysonPlugin
