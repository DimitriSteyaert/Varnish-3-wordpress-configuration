##Varnish 3 configuration file for Wordpress sites

###The Setup
This configuration file can be used to quickly configure your Varnish 3 installation. I have created this file based on Wordpress sites that I am hosting on my webserver but the major part of this configuration file can be used as a global (basic) configuration.

###Installation
* First of all create a local backup of your current varnish configuration file: `cp /etc/varnish/default.vcl /etc/varnish/default.vcl.bak`
* Then edit the file /etc/varnish/default.vcl and add the contents of my configuration
* Restart varnish: `/etc/init.d/varnish restart`
