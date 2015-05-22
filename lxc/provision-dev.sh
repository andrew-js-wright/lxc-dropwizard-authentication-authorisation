# /usr/bin bash
function wait_on_ip {
    # Loop until the web container's IP has been assigned
    while [ -z $ip ] ; do
        ip=$(sudo lxc-info -n$1 -iH);
        sleep 1s;
    done
}

# Create base container
if ! sudo lxc-ls | grep service-base > /dev/null
then
	sudo lxc-create -t ubuntu -n service-base
	sudo lxc-start -n service-base
	sudo lxc-attach -n service-base -- << SCRIPT
sudo apt-get update
sudo apt-get install --fix-missing -y openjdk-7-jre
SCRIPT
fi
sudo lxc-stop -n service-base

# Destroy existing containers
sudo lxc-destroy -f -n frontend 
sudo lxc-destroy -f -n authorisation
sudo lxc-destroy -f -n authentication
sudo lxc-destroy -f -n person
sudo lxc-destroy -f -n session

# Clone other java dependent containers
sudo lxc-clone -o service-base -n frontend
sudo lxc-clone -o service-base -n authorisation
sudo lxc-clone -o service-base -n authentication
sudo lxc-clone -o service-base -n person
sudo lxc-clone -o service-base -n session

# Move application specific files into root file systems
sudo mkdir /var/lib/lxc/frontend/rootfs/frontend
sudo cp /host/volume-frontend/* /var/lib/lxc/frontend/rootfs/frontend

sudo mkdir /var/lib/lxc/authorisation/rootfs/authorisation
sudo cp /host/volume-authorisation/* /var/lib/lxc/authorisation/rootfs/authorisation

sudo mkdir /var/lib/lxc/authentication/rootfs/authentication
sudo cp /host/volume-authentication/* /var/lib/lxc/authentication/rootfs/authentication

sudo mkdir /var/lib/lxc/session/rootfs/session
sudo cp /host/volume-session/* /var/lib/lxc/session/rootfs/session

sudo mkdir /var/lib/lxc/person/rootfs/person
sudo cp /host/volume-person/* /var/lib/lxc/person/rootfs/person

bash /host/image-nginx-lua/provision.sh

# Move upstart configuration files into the correct target directory
sudo cp /host/upstart/frontend.conf /var/lib/lxc/frontend/rootfs/etc/init
sudo cp /host/upstart/authorisation.conf /var/lib/lxc/authorisation/rootfs/etc/init
sudo cp /host/upstart/authentication.conf /var/lib/lxc/authentication/rootfs/etc/init
sudo cp /host/upstart/person.conf /var/lib/lxc/person/rootfs/etc/init
sudo cp /host/upstart/session.conf /var/lib/lxc/session/rootfs/etc/init

# Start up the containers
sudo lxc-start -n frontend
sudo lxc-start -n authorisation
sudo lxc-start -n authentication
sudo lxc-start -n session
sudo lxc-start -n person

# Network containers
wait_on_ip frontend
echo "$(sudo lxc-info -n frontend -iH) frontend" | sudo tee -a /var/lib/lxc/web/rootfs/etc/hosts
wait_on_ip authentication
echo "$(sudo lxc-info -n authentication -iH) authentication" | sudo tee -a /var/lib/lxc/web/rootfs/etc/hosts
wait_on_ip session
echo "$(sudo lxc-info -n session -iH) session" | sudo tee -a /var/lib/lxc/web/rootfs/etc/hosts

wait_on_ip authorisation
echo "$(sudo lxc-info -n authorisation -iH) authorisation" | sudo tee -a /var/lib/lxc/person/rootfs/etc/hosts
wait_on_ip person
echo "$(sudo lxc-info -n person -iH) person" | sudo tee -a /var/lib/lxc/frontend/rootfs/etc/hosts


# Set up firewall rule on host to forward port 80 to web container
sudo iptables --flush PREROUTING -t nat
wait_on_ip web
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to $(sudo lxc-info -n web -iH):8080
