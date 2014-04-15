bootstrap-salt NOT YET READY!
==============

Ozone.io's provisioner for salt:

A script that installs, configures and runs salt, that works on all recent unix distributions.

The helper functions and the installation-script that installs chef are created by Opscode. Thank you!

### Prerequisites
* A Vanilla distribution: Do not have chef pre-installed by a third party.

### OS supported

Tested on the following using vagrant but should support more in the future. (Or already does)

* _Ubuntu_: 12.04, 12.10, 13.04, 13.10
* _CentOS_: 5.8, 5.10, 6.5
* _Debian_: 6.0.8 (Squeeze), 7.4 (Wheezy)
* _fedora_: 19,20

### Purpose:
This script as well as its cousins [bootstrap-puppet](https://github.com/ozone-io/bootstrap-puppet), [bootstrap-chef](https://github.com/ozone-io/bootstrap-chef) and its future cousins are part of the [ozone.io](http://ozone.io) project that aims to abstract various cloud providers and configuration management tools in a simple understandable manner to test and deploy large clusters.

Underlying principles:

* Any state introduced except by your configuration management tool "taints" the image, as your actions will be not be reproducable by your co-workers or those that will inherit your work.
* Do not use snapshots or cloning of your machines when launch-time is not important. Rather re-deploy the same base-image and provision it from beginning to end. This will make sure the state of your cluster is always reproducable.
* Reap the benefits of using vanilla cloud images by experimenting with various operating system versions. Upgrading a distribution will never be easier than this and at most involve you to change your configuation management parameters accordingly, which is what the cm-tool is expected of.

### How to use:
Default with no environment variables, only salt is installed and nothing else is modified.

TODO: The configure and run phase are still being developed.

### Test

The test folder contains settings that will install and configure ntp, nginx and mysql.

Examine the Vagrantfile for the distro you would like to test. Then for i.e. fedora20, excute the following:

    vagrant up fedora20

Vagrant will automatically execute the test script and execute the stages install,configure and run.

* Requires vagrant 1.5+ (uses the Vagrantcloud for boxes)
