#Micro-services on LXC
I want to explore [Linux Containers](https://linuxcontainers.org) in order to
see how difficult it is to set up the development environment for a sample
micro-service architecture using
[LXC](https://linuxcontainers.org/lxc/). I will discuss what I found upfront
and then walk through the entire process allowing you to do the same.
The design of the implemented architecture is covered in detail
in [this blog post](https://stevenwilliamalexander.wordpress.com/2015/05/11/microservice-authentication-and-authorisation-using-docker/)
so I'll not repeat that content here.

#LXC
[LXC](https://linuxcontainers.org/lxc/) is a
tool set used for creating and managing containers on the Linux kernel.
It is what [Docker](docker.io), the
developer friendly containerisation platform, was originally built on. 
There has been a lot of hype about docker and how simple it is to create a
container on a developer's laptop and run it on a production/test
environment. Docker has made containerisation a piece of cake and abstracted
a lot of the detail beneath it's shiny interface. Before I jump on the bandwagon I
wanted to understand those details a little better hopefully
shedding some light on what exactly Docker is bringing to the table and the
situations where it might be more appropriate to use something closer
to the metal.

#Findings 
It is completely possible to set up a containerised micro-services environment 
using LXC. It can be easily scripted to allow for 
a high degree of customisation (anything you can do on the host and guest operating
systems is possible). It is relatively quick compared to virtual machines but
base images take a while to build.

##Networking
LXC takes care
of a lot of the network setup when a container is created and can be configured 
to do this in several different ways by default it creates a bridge interface on 
the host and links all containers together through it. This allowed us to get 
our containers talking to each other quickly. Other networking options are available 
and are helpfully explored [here](containerops.org/2013/11/19/lxc-networking/). 

##Performance

- Clean deployment takes 20 minutes.
- Deploy from cached base boxes takes 2.5 minutes.

These results were slower than I had expected. They could be improved using
[BTRFS](https://btrfs.wiki.kernel.org/index.php/Main_Page) which LXC supports
but I didn't want to go into that here.

##Security
Currently LXC, by default, runs it's containers on the host system as root. This means
that if someone where able to 'break out' of their container they would have root access
to the host and be able to wreak all kinds of havoc. LXC has introduced a feature called
unprivileged containers whereby it is possible to run a container as an unprivileged user.
This means that if a compromise was found in the underlying technology of container isolation
you would still have the protection of the Linux kernel's user privileges.
I haven't fully explored how to do this in this article as this is aimed a development
environment.

##File System
By default LXC uses the same file system as the host giving the host complete 
access to the each container's file system which is used extensively in this case 
study to easily copy configuration files across to the guest container. This is
customisable and can be pointed to a separate file system/device.

##Container Migration
I expected to be able to easily create a base container on my machine and seamlessly 
port it over to a college's machine with minimal disruption although this is technically
possible it's nowhere near as easy as sharing docker images. 

##Scripting
I found the provisioning of the container the most time consuming part of pulling this all
together and I imagine if this was being used over a large team of developers it would
time consuming to keep on top of the provisioning scripts. There are [python](https://github.com/lxc/python2-lxc) 
and [C](https://linuxcontainers.org/lxc/documentation/) APIs available which I would 
like to look as I imagine that would easier to build and maintain than BASH.

#Technical Implementation 
Lets look again at the [authentication and authorisation application
](https://stevenwilliamalexander.wordpress.com/2015/05/11/microservice-authentication-and-authorisation-using-docker/)
we will deploy onto LXC. The linked article is great at clearly outlining why
containerisation can be useful and how the micro-service model
lends itself to containerisation. 

The complete source code of the LXC implementation can be found on
[github](https://github.com/andrew-js-wright/lxc-dropwizard-authentication-authorisation).

##Prerequisites 
If you want to follow along with this post here are the tools
you'll need:

- [Vagrant](http://www.vagrantup.com)
- [Gradle](http://gradle.org/)
- [Java 7](http://www.oracle.com/technetwork/java/javase/7u-relnotes-515228.html)

You will also need to build the application before we can deploy it. This is
done using Gradle as follows:

```console
me@local-machine$ gradle buildJar 
```

##Deployment Process

Software developers have a bit of a reputation for not being overly concerned
with what happens after their code has left their machine. I am sure that
there are some developers for which this is true, however in my experience,
with huge developer bias, the problem is quite often that developers feel that
they lack the appropriate visibility of the landscape to which their code is
being deployed to. Developing against containers helps to bring that land scape
closer, allowing the developers to see first hand the hills and valleys their
code will have to traverse in the wild. For me, this is the big reason why
containers are so useful. The sooner a developer knows something won't work
on the target OS the sooner they can fix it. Also, the more comfortable
they feel with the deployment process the more people can help out when
things go wrong down stream.

In order to get from freshly pressed JARs
to applications running on containers the JARs to have to take a 3 step
journey:

1. Local machine -> Container host
2. Container host -> Container 
3. Execution within the container

To make sure everything's working the web server should be accessible from the
local machine.

###Step 1: From Local Machine to Container Host

Vagrant has a nice clean interface for mounting host directories onto a guest VM
so that's what I'll use for this. If you look at the
[Vagrantfile](https://github.com/andrew-js-wright/lxc-dropwizard-authentication-authorisation/blob/master/Vagrantfile)
I'm using, you'll see it's booting a Ubuntu trusty box (downloading the base
image if it isn't installed already), sharing the [build output
directory](https://github.com/andrew-js-wright/lxc-dropwizard-authentication-authorisation/tree/master/lxc)
from the host and installing LXC. This can be done locally by running the
following command from the same directory as the `Vagrantfile`:

```console
me@local-machine$ vagrant up 
```

###Step 2: Deploy Artefacts to Containers

As part of the provisioning which is done by vagrant the containers are
created, provisioned and the appropriate application files are copied across
into each containers file system. I've broken this out into its own [bash
script](https://github.com/andrew-js-wright/lxc-dropwizard-authentication-authorisation/blob/master/lxc/provision-dev.sh) for easy reference.

The lines of the provision script which we are concerned about here are as
follows:

```bash
# Create our base container
sudo lxc-create -t ubuntu -n service-base

# Start the base container
sudo lxc-start -n service-base

# Install the Java Run-time Environment
sudo lxc-attach -n service-base -- <<SCRIPT
    sudo apt-get update
    sudo apt-get install --fix-missing -y openjdk-7-jre
SCRIPT
```

That's our base java container built. We will use that to create all of the
service containers which use Java. The first one we will create is the 
`frontend` container.

```bash
# Stop the base container
sudo lxc-stop -n service base

# Clone it into an application specific container
sudo lxc-clone -o service-base -n frontend

# Copy across application specific files
sudo mkdir /var/lib/lxc/frontend/rootfs/frontend
sudo cp /host/volume-frontend/\* /var/lib/lxc/frontend/rootfs/frontend
sudo cp /host/upstart/frontend.conf /var/lib/lxc/frontend/rootfs/etc/init

# Start the application container
sudo lxc-stop -n frontend
```

Remember this is all run on the container host using vagrant which means the
`/host/` directory is the location we mounted directly from the development machine.

In order to prove that we can access the application files from within the
containers let dive inside and poke around.

```console
# Jump onto host VM which has been provisioned with vagrant 
me@local-machine$ vagrant ssh                                     

# Run a bash shell inside the running frontend container
vagrant@vagrant-ubuntu-trusty-64:~$ sudo lxc-attach -n frontend

# List the files in the frontend directory within the container
root@frontend:/# ls -l /frontend
total 14132
-rw-r--r-- 1 root root      412 May 21 17:13 config.yml
-rw-r--r-- 1 root root 14464552 May 21 17:13 FrontendApplication.jar
```

Great, we've established that we can get something that has been developed on
a developers machine, onto an LXC container relatively painlessly. Now how do
we make use of this? We still need to ensure the container has the required
dependencies (i.e. the java run time environment) and we need to run our app.

###Step 3: Run Applications on said Containers

I'm going to use
Ubuntu's default task and services handler
[upstart](http://upstart.ubuntu.com/) to manage the service. This gives us the
benefit of being able to allow our service to run in the background being
supervised by a robust manager which will start the service automatically and restart
it if it dies. To do this all we need is a
configuration file following file at the location `/etc/init/frontend.conf`
which will have the following contents:

```bash
# Front ends init script for upstart 
start on file system and net-device-up IFACE!=lo 
script 
    java -jar /frontend/FrontendApplication.jar
    server /frontend/config.yml end 
script 
respawn 
```

We'll create this file in our mounted host directory and copy it across with
another line in our provisioning script below:

```bash
# On the vagrant host copy the upstart configuration from the host system into the container init directory 
sudo cp /host/frontend.conf
/var/lib/lxc/frontend/rootfs/etc/init 
```

We can test that our service is running on the container by running the
following command on the vagrant host. If it returns one line then we've got a
java process listening on the correct port.

```console
vagrant@vagrant-ubuntu-trusty-64:~$ sudo lxc-attach -n
frontend -- netstat -plunt | grep java | grep :8081 tcp6       0      0 :::8081
:::\*                    LISTEN      765/java 
```

Tada! We have successfully implemented our development pipeline, getting our code
from our development machine to running on a container within a production like
OS.

We now want to do the same for the rest of our services so they are all
deployed in their own containers. Instead of creating brand new container we
can simply clone the service-base container we made as it already has the required
run time environment.

All of the micro-service containers are basically the same, if you have a look
in the [lxc/upstart](https://github.com/andrew-js-wright/lxc-dropwizard-authentication-authorisation/tree/master/lxc/upstart) 
directory you'll see that I've basically copied the
front ends start up script across and extended the [provision script](https://github.com/andrew-js-wright/lxc-dropwizard-authentication-authorisation/blob/master/lxc/provision-dev.sh)
to copy across all of the required configuration files based on the frontend
container. The outlier here is the web box which has a different set of
dependencies and uses nginx to act as a reverse proxy, co-coordinating
communication between the user and the underlying services. 

###The web container 
Because the web container is a little different I felt it
made sense to put it's provisioning in a [separate script](https://github.com/andrew-js-wright/lxc-dropwizard-authentication-authorisation/blob/master/lxc/image-nginx-lua/provision.sh) 
to easily see what's going on.

In this script we'll create the container and install
[openresty](http://openresty.org/) along with its dependencies. Note we can use
[here-docs](http://tldp.org/LDP/abs/html/here-docs.html) to send multiple lines
to the lxc-attach utility.

```bash
sudo lxc-create -t ubuntu -n web sudo lxc-start -n web

sudo lxc-attach -n web -- apt-get update sudo lxc-attach -n web -- apt-get -y
install libreadline-dev libncurses5-dev libpcre3-dev libssl-dev perl
build-essential curl

sudo lxc-attach -n web --  << SCRIPT curl -0
http://openresty.org/download/ngx_openresty-1.7.10.1.tar.gz tar xzvf
ngx_openresty-1.7.10.1.tar.gz cd ngx_openresty-1.7.10.1 ./configure
--with-luajit --with-http_gzip_static_module --with-http_ssl_module
--with-pcre-jit make make install start web SCRIPT 
```

The web provision script is ran from the original provision script. Once
we have re-provisioned the boxes (either by running `vagrant provision` or
`vagrant destroy && vagrant up`) we can test that nginx is running and listening
on the desired port as follows.

```console
me@local-machine$ vagrant ssh
vagrant@vagrant-ubuntu-trusty-64:~$ curl $(sudo lxc-info -iH -n web):8080
<html>
<head><title>502 Bad Gateway</title></head>
<body bgcolor="white">
<center><h1>502 Bad Gateway</h1></center>
<hr><center>openresty/1.7.10.1</center>
</body>
</html>
```

That isn't just any old error we're getting back from the curl that's an
NGINX error, which means the web server is listen on the web container's
port 8080 and we can access it from the host. In order to move past a
`Bad Gateway` error we need to let NGINX know where the services it's
trying to talk are. In fact we need to let all of the services know where
to look for a given service. We'll do this now.

###Wiring Containers Together 
By default when LXC creates a container it adds a
virtual ethernet connection to a bridge on the host machine. This allows the
host to access the container and visa versa. Lets ping a container from the
vagrant host to prove that we can communicate with it.

```console
vagrant@vagrant-ubuntu-trusty-64:~$ ping -c 3 $(sudo
lxc-info -n frontend -iH) PING 10.0.3.108 (10.0.3.108) 56(84) bytes of data.
64 bytes from 10.0.3.108: icmp_seq=1 ttl=64 time=0.039 ms 
64 bytes from 10.0.3.108: icmp_seq=2 ttl=64 time=0.085 ms 
64 bytes from 10.0.3.108: icmp_seq=3 ttl=64 time=0.130 ms

--- 10.0.3.108 ping statistics --- 3 packets transmitted, 3 received, 0% packet
loss, time 2000ms rtt min/avg/max/mdev = 0.039/0.084/0.130/0.038 ms 
```

Note the nested
[lxc-info](http://man7.org/linux/man-pages/man1/lxc-info.1.html) utility gives
us a convenient way of accessing the container's IP address. It's one thing
being able to ping the machine but in order to get any use out of the container
we need to be able to connect to the service which it is running.

In this architecture we are using the web container as a reverse proxy. This
means that it will need to know the IP addresses of services it is proxying for
and those services will need to know the address of any service they in turn want 
to call. In the configuration of the application we refer to other services using
their host name. We'll use [hosts
files](http://linux.die.net/man/5/hosts) to store the links between host names
and IP addresses at the container level. Note that all of these services can
already communicate with each other using IP addresses because of the bridge,
we're just making it a bit more readable and maintainable.

We can propagate these as soon as we start the containers and the DHCP server on the
network bridge assigns each container with an IP address.

See the following section of the provision script:

```bash
# Network containers 
echo "$(sudo lxc-info -n frontend -iH) frontend" | sudo tee -a /var/lib/lxc/web/rootfs/etc/hosts 
echo "$(sudo lxc-info -n authentication -iH) authentication" | sudo tee -a /var/lib/lxc/web/rootfs/etc/hosts 
echo "$(sudo lxc-info -n session -iH) session" | sudo tee -a /var/lib/lxc/web/rootfs/etc/hosts

echo "$(sudo lxc-info -n authorisation -iH) authorisation" | sudo tee -a /var/lib/lxc/person/rootfs/etc/hosts 
echo "$(sudo lxc-info -n person -iH) person" | sudo tee -a /var/lib/lxc/frontend/rootfs/etc/hosts 
```

Once this has been run we can ping the frontend container from the web one as
follows:

```console
vagrant@vagrant-ubuntu-trusty-64:~$ sudo lxc-attach -n web -- ping frontend -c 3 
PING frontend (10.0.3.151) 56(84) bytes of data.
  64 bytes from frontend (10.0.3.151): icmp_seq=1 ttl=64 time=0.141 ms
  64 bytes from frontend (10.0.3.151): icmp_seq=2 ttl=64 time=0.096 ms 
  64 bytes from frontend (10.0.3.151): icmp_seq=3 ttl=64 time=0.106 ms

--- frontend ping statistics --- 
3 packets transmitted, 3 received, 0% packet loss, 
time 1998ms rtt min/avg/max/mdev = 0.096/0.114/0.141/0.021 ms 
```

Lets try to hit the frontend service which is running on the frontend box from
the web container now:

```console
vagrant@vagrant-ubuntu-trusty-64:~$ sudo lxc-attach -n web -- curl frontend:8081 | grep Persons 
<h2><a href="/persons">View Persons</a></h2> 
```

We have successfully established the link
between the web container and the service running on the frontend container.

##Access From Browser 
So we have a fully operational system architecture living
inside our host vagrant machine. For developing web applications however,
SSHing into a host to test functionality won't give us a very good
idea of how we're getting so lets allow the laptop to look inside the box.

As discussed above when lxc creates containers it puts them all onto a bridge
which uses [NAT](http://en.wikipedia.org/wiki/Network_address_translation) to
hide the underlying network from everything passed external to the host. This
is kind of similar to how a home router hides individual devices from the
internet. In the same way, if we want to expose an individual device (i.e. a
container) to the wider network we will need to modify the router's (in this
case the vagrant host machine's) firewall to forward requests to correct port.

In order to do this we want to add a port forwarding rule to the NAT table in
the firewall using [iptables](http://en.wikipedia.org/wiki/Iptables). This will
go in the PREROUTING section and ensure that any
requests coming in on port 80 of the host get sent to the web container on port
8080. We can do this and verify that the firewall has been updated with the
following commands.

```console
vagrant@vagrant-ubuntu-trusty-64:~$ sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to $(sudo lxc-info -iH -n web):8080 
vagrant@vagrant-ubuntu-trusty-64:~$ sudo iptables -t nat -L 
Chain PREROUTING (policy ACCEPT) target     prot opt source               destination
DNAT       tcp  --  anywhere             anywhere             tcp dpt:http to:10.0.3.126:8080

Chain INPUT (policy ACCEPT) target     prot opt source                 destination

Chain OUTPUT (policy ACCEPT) target     prot opt source                   destination

Chain POSTROUTING (policy ACCEPT) target     prot opt source destination 
MASQUERADE  all  --  10.0.3.0/24         !10.0.3.0/24 
```

Now the final test. Log out of the vagrant machine by typing `exit` and navigate
to `localhost:8080` on the web browser. This should show you the first page of the application.

#Redeploying Code
Now when you make a change to the source code and rebuild the jars a `vagrant provision` run will
recreate your containers and deploy the JARs onto a fresh environment making sure you don't 
get away with any hacky manual fixes which aren't stored in a provision script somewhere.
