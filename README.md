# Welcome to Rumpy

Rumpy is some kind of framework to make up your own jabber bot quickly.
It uses [ActiveRecord](https://github.com/rails/rails/tree/master/activerecord) and [XMPP4R](http://home.gna.org/xmpp4r/).

Our goal is **'DO NOT REINVENT THE WHEEL'**.

## Features

* Forget about xmpp-related things. Just set your login and password.
* Forget about database-related things. Just set your database preferences.
* Write logic using `ActiveRecord` and callback functions.

## Getting started

### Configs

Rumpy uses 3 configs:

* *database.yml* :: Your bot's database preferences.
* *lang.yml*     :: Your bot's responces. Append to existing keys more answers and use them like `@lang['someanswer']`. There **MUST** be at least 3 keys: `hello` (_used when somebody adds bot_), `stranger` (_used when somebody trying to speak with bot without authorization_) and `authorized` (_used when bot gets authorization_).
* *xmpp.yml*     ::  Your bot's jabber account settings.

Look at Examples section to see this configs.

### ActiveRecord models

Implement your `ActiveRecord` models.
You have to implement at least one model, for users.

### Prepare your database

### Your bot's class

#### `Rumpy::Bot` module

You have to mix in your bot's class the `Rumpy::Bot` module:

    include Rumpy::Bot

#### Instance variables

**Rumpy** uses next instance variables:

* `@models_files`    ::  Array of your models files.
* `@config_path`     ::  Path to directory, containing all ruby configuration files. Default is `'config'`.
* `@main_model`      ::  Symbol, that stands for main model. For example, if your main model is `User`, you have to set `@main_model = :user`. And this is default.
* `@pid_file`        ::  Location of the file to which pid of detached process will be saved. Default is `NameOfYourBotClass.downcase + '.pid'`.
* `@log_file`        ::  Location of the logfile. Default is `STDERR`.
* `@log_level`       ::  Logging severity threshold. Possible values are the same the logger from standard library has. Default is `Logger::INFO`.
* `@log_shift_age`   ::  Number of old log files to keep, or frequency of rotation (`daily`, `weekly` or `monthly`). Default is `0`.
* `@log_shift_size`  ::  Maximum logfile size. Default is `1048576`.
* `@logger`          ::  If you need more accuracy in configuring logger, simply create one. It have to be compatible with standard library's `logger`.
* `@bot_name`        ::  Name of the bot. Default is name of bot's class.
* `@bot_version`     ::  Optional version of the bot. Default is `'1.0.0'`.

#### Instance methods

**Rumpy** needs only three methods:

* `backend_func() -> [[receiver, message]*]` :: This _optional_ method is running all the time in the loop. Returns array of pairs `[receiver, message]`.
* `parser_func(msg) -> pars_result`          :: This method parses any incoming message and returs results of parsing.
* `do_func(usermodel, pars_results) -> msg`  :: This method uses results from `parser_func`, doing some stuff with model of user, from whom the message was received. Returns the answer to this user.

_Hint_: empty answer will not be sent.

### Run bot

You can run your bot without detaching:

    Rumpy.run YourBotClassName.new

Or with detaching:

    bot = YourBotClassName.new
    #To start your bot:
    Rumpy.start bot
    #To stop it:
    Rumpy.stop bot

## Examples

Look at

* [CuteBot](https://github.com/MPogoda/CuteBot)
* [yatodo](https://github.com/MPogoda/yatodo)
* [Noty](https://github.com/Ximik/Noty)

## Contacts

Feel free to contact us about any questions related to **Rumpy**.

## License

**Rumpy** is released under the MIT license.
