---
layout: post
title: 'Docker: Can you say "Best thing ever"?'
date: 2014-09-28 04:14:34.000000000 -06:00
---
For the past few days, I've been acquainting myself with [Docker](https://www.docker.com/). Saying "it's great" is a huge understatement.

## What is Docker?
<img src="{{ site.baseurl }}/images/docker-logo.png" style="float:right" width="200px" />

Docker is a open-source project that allows running encapsulated applications inside software containers (kernel-level virtualization). It is usually compared to virtual machines, which offer similar encapsulation but at a much higher overhead.

In Layman's terms, Docker is a much more lightweight, flexible and limited version of a VM. However, this description doesn't do Docker justice.


<div style="clear:both"></div>

## Docker programs run in isolation, natively on a Linux host.

This is what sets Docker apart from other VMs. Docker doesn't emulate a kernel, but embraces the host's kernel. Due to this fact, Docker has virtually no overhead compared to full-blown VMs.

Docker is Linux-specific, so it cannot be run natively on Windows or Mac OS X. If you'd like, you can use [Vagrant](https://www.vagrantup.com/) or boot2docker on Windows and OS X to set up a lightweight Linux VM with Docker installed.

***Update, 2014/10/16:*** There are new plans for a Windows version of Docker, but it is presumably incompatible with Linux-based images.

## Why use Docker?

### Consistency
Docker is a relatively easy way to ensure the same software stack and configurations exist on multiple machines. Whether it's testing or production, it's all the same.

There is no risk of a botched install due to some weird pre-existing configuration on a machine. Every instance of a Docker image always behaves the Exact. Same. Way.


### It self-documents your installs and configurations

To me, this is the single most important aspect of Docker from a *maintainability* perspective.
In a world without Docker, it's too easy to install and configure applications in an ad-hoc fashion. When you're rebuilding the server six months later, you're going to forget what you did to get everything to work.

* Which Apache modules need to be enabled?
* Which command starts the daemon (ie. to use from supervisord)?
* Error on line 423 of derp.conf
* Environment variables?
* It's different on Fedora, isn't it?

Aside from doing nothing, there are a few traditional options: Thoroughly document all the steps in a wiki, or write scripts to configure everything.

You could write a script in bash or similar, using `apt-get install` and other goodies to install all dependencies. This is a bad idea.
It might work for ad-hoc setups, but it's fragile and definitely not scalable.

Bash scripts as mentioned depend on your machine being in a known good state. If your existing machine deviates from this state, then anything can happen. What if a pre-existing service uses a needed port? What happens if you run the script twice?

With Docker, you're always given a clean slate.

```dockerfile
FROM debian:wheezy

RUN apt-get update && apt-get install apache2
RUN a2enmod rewrite

# Add mysite.conf from local filesystem
ADD mysite.conf /etc/apache2/sites-enabled/mysite

# Enable mysite
RUN a2dissite 000-default && a2ensite mysite

# Run!
CMD ["apache2", "-DFOREGROUND"]
```

### Fast iteration, disposable containers
Disposable containers are great for experimentation. If something doesn't work, just throw it away.

You can even go on a power trip and trash the entire container with `rm -rf /`. You can even do it 20 times in a row. You know you want to.

```bash
$ docker run -it debian:wheezy
root@1fd4be82a462:/# rm -rf *
  <serveral errors later...>
root@1fd4be82a462:/# ls
bash: /bin/ls: No such file or directory
root@1fd4be82a462:/# exit
$
```



### The community has already done the work for you.

Docker has a [public registry of images](https://registry.hub.docker.com/). It includes official base images for Ubuntu, Debian, CentOS, etc., for you to build on top of.
You can try MySQL, node.js, nginx, PHP, MongoDB... all with a simple `docker pull` at the command line.

~~*Fun fact:* This blog is powered by [Ghost](https://ghost.org/), the wonderful blogging software. It is set up on AWS using [this Docker repo](https://registry.hub.docker.com/u/dockerfile/ghost/).
If Ghost requires an update, all I need to do is rebuild the image with `docker build -t <name> .` and deploy a new container. Pulling will automatically download any changes.~~

***Update, 2015/04/14:*** This blog is now hosted on GitHub Pages using Jekyll.

### You can commit Dockerfiles into source control (Git, Mercurial, Subversion...).

A `Dockerfile` file is a specification of the steps required to build a Docker image. As this is a text file typically not exceeding a few kilobytes, it's very source control friendly.

This is a huge win for software developers. Everyone on a team can pull the exact same image, and have it run the exact same way on all machines.

Most importantly, `Dockerfile`s self-document how to get a project running.
