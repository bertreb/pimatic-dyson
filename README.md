# pimatic-dyson
Plugin for connecting Dyson Pure devices to Pimatic

The plugin can be installed via the plugins page of Pimatic.
This plugin works for Dyson Pure devices.

## Config of the plugin
```
{
  email:       The email address of your Dyson account
  password:    The password of your Dyson account
  countryCode: The countryCode like 'DE' or 'NL'
  polltime:    Time for update in values (default 1 minute)
  debug:       Debug mode. Writes debug messages to the Pimatic log, if set to true.
}
```

## Config of a DysonDevice

Devices are added via the discovery function. Per registered Dyson device a DysonDevice is discovered unless the device is already in the config.
The automatic generated Id must not be change. Its based on the serial with prefix 'dyson-'. Its an unique reference to your device. You can change the Pimatic device name after you have saved the device.

```
{
  serial: 	De serial number of your Dyson device
  type: 	The type id of your Dyson device
  product: 	The product name of your Dyson device
  version: 	The version number
}
```

The following attributes are updated and visible in the Gui.

```
deviceFound: "If your Dyson device is found in the local network"
deviceStatus: "If device is on or off"
temperature: "Temperature"
airQuality: "The air quality"
relativeHumidity: "The relative humidity"
fanStatus: "If the fan is on or off"
fanSpeed: "The speed of the fan (0-100)"
rotationStatus: "If the rotation is switched on or off"
autoOnStatus: "If the auto modus is on or off"
```

The device can be controlled via rules.

The action syntax:
```
  dyson <DysonDevice Id>
  	on | off
  	auto [ on | off]  
  	fan [ on | off]
  	speed [ <0-100> | $speed-var]
  	rotation [ on | off ]

```

The $speed-var must be a number between 0-100

The DysonDevice is still in alfa test. You are welcome to test it.

----
This plugin needs minimal node version 10!
