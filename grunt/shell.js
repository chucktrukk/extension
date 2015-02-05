module.exports = function() {
    'use strict';

    return {
        'sign-xpi': {
            command: [
                'rm -f ./build/mailfred.signed.xpi',
                'xpisign -k ./certs/code_signing/key.pem ./build/mailfred.xpi ./build/mailfred.signed.xpi'
            ].join(' && ')
        },
        "update-xpi": {
            "options": {
                "stderr": false,
                "failOnError": false
            },
            // for this to work
            // https://addons.mozilla.org/en-US/firefox/addon/autoinstaller/
            // must be installed in the Firefox you are using
            "command": "wget --post-file=build/mailfred.xpi http://localhost:8888/"
        },
        'update-max-version-cfx': {
          command: './updateInstallRdf.js'
        },
        "update-rdf": {
            command: 'tmp/mxtools/uhura -o build/update.rdf -m -k certs/firefox/updateRdfKeyFile.pem build/mailfred.xpi http://bla/mailfred.xpi firefox/appvers.txt'
        }
    };
};