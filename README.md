## Setting up your environment

Install Ruby using RVM
https://rvm.io/


```
rvm install 2.4.1
rvm --default use 2.4.1
```

```
gem install bundler
bundle install
```

To checkout all submodules in this repo:
```
git submodule update --init --recursive
```

To start serving locally:
```
./serve.sh
```
