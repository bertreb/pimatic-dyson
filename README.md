# pimatic-dyson
Plugin for connecting Dyson Pure devices to Pimatic

The plugin is based on an embedded and modified version of the dyson-purelink library of (K.Augenberg)[https://github.com/auchenberg].
The plugin can be installed via the plugins page of Pimatic.
This plugin works for Dyson Pure devices.

## Config of the plugin
```
{
  email:       Email address of your Dyson account
  password:    Password of your Dyson account
  countryCode: CountryCode like 'DE' or 'NL'
  polltime:    Time for update in values (default 1 minute)
  debug:       Debug mode. Writes debug messages to the Pimatic log, if set to true.
}
```

## Config of a DysonDevice

Devices are added via the discovery function. Per registered Dyson device a DysonDevice is discovered unless the device is already in the config.
The automatic generated Id must not be change. Its based on the serial with prefix 'dyson-'. Its an unique reference to your device. You can change the Pimatic device name after you have saved the device.

```
{
  serial:   Serial number of your Dyson device
  type:     Type id of your Dyson device
  product:  Product name of your Dyson device
  version:  Version number
}
```

The following attributes are updated and visible in the Gui.

```
deviceFound:      Dyson device is found in the local network
deviceStatus:     Device is on or off
temperature:      Air temperature
airQuality:       Air quality
relativeHumidity: Relative humidity
fanStatus:        Fan is on or off
fanSpeed:         Speed of the fan (0-100)
rotationStatus:   Rotation is switched on or off
autoOnStatus:     Auto modus is on or off
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
