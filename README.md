# CityVoice-Builder for Heroku

## Deployment

Set your OAuth ID (from Heroku):

    $ heroku config:set HEROKU_OAUTH_ID=lolmyoauthid
    $ heroku config:set HEROKU_OAUTH_SECRET=lolmysecret

Push:

    $ git push heroku master

Provision Heroku's RedisToGo add-on:

    $ heroku addons:add redistogo:small

(Details and pricing [$39/mo for the small add-on shown above] can be found at: https://addons.heroku.com/RedisToGo )

Copyright Code for America Labs 2014, MIT License

