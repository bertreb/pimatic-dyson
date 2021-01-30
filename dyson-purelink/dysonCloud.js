var request = require('request-promise-native');
var crypto = require('crypto');

class DysonCloud {

    constructor() {
        this.api = 'https://appapi.cp.dyson.com'
        this.auth = {}
    }

    authenticate(email, password, country) {
        if (!country) {
            country = 'US'
        }

        var options = {
            url: `${this.api}/v1/userregistration/authenticate?country=${country}`,
            method: 'post',
            body: {
                Email: email,
                Password: password
            },
            agentOptions: {
                rejectUnauthorized: false
            },
            headers: {'User-Agent': 'DysonLink/29019 CFNetwork/1188 Darwin/20.0.0'}, //'Mozilla/5.0'},
            json: true
        }

        //console.log("options: "+JSON.stringify(options,null,2));

        return request(options)
            .then(info => {
                this.auth = {
                    account: info.Account,
                    password: info.Password
                }
                //console.log("Authenticated: "+JSON.stringify(info))
                return this.auth
            })
            .catch( err=> {
                console.log("error authenticate: " + JSON.stringify(err,null,2))
            })
    }

    logout() {
        this.auth = {}
    }

    getCloudDevices() {
        var options = {
            url: `${this.api}/v2/provisioningservice/manifest`,
            method: 'get',
            auth: {
                username: this.auth.account,
                password: this.auth.password,
            },
            agentOptions: {
                rejectUnauthorized: false
            },
            headers: {'User-Agent': 'DysonLink/29019 CFNetwork/1188 Darwin/20.0.0'}, //'Mozilla/5.0'},
            json: true
        }

        return request(options);
    }

};

module.exports = DysonCloud;
