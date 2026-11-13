# Крестики-нолики

## Description

Игра в крестики-нолики на доске 10/10 онлайн. Приложение хранит историю ходов (для будущего отображения). В данных заложена возможность в будущем масштабировать доску под необходимый размер. Первые 2 человека перешедшие по ссылке становятся игроками - следующие наблюдателями.

Стек: 
- авторизация - devise;
- фронтэнд - vue;
- игра рассчитывает алгоритм победы и определяет невозможость дальнейших ходов (ничья);
- игра использует websockets - нет необходимости перезагружать страницу;
- для начала игры - перешлите ссылку другу, либо передайте id игры;

## Running

[https://xoxotsf.herokuapp.com/](https://xoxotsf.herokuapp.com/)

### Локальный запуск

Для текущей сборки используются Ruby 3.0.1, Node.js 24, Yarn 1 и PostgreSQL;
для WebSocket в development также нужен Redis. После запуска PostgreSQL и Redis:

```sh
rvm use 3.0.1
bundle install
yarn install --frozen-lockfile
bundle exec rails db:prepare
NODE_OPTIONS=--openssl-legacy-provider bundle exec rails server
```

Webpack 4 и его старые загрузчики требуют legacy OpenSSL provider в Node 24.
Эта временная настройка включает устаревшие алгоритмы только в процессе Node;
проверка Yarn в Webpacker отключена из-за замены `node-sass` на Dart Sass,
поэтому после изменения зависимостей повторяйте `yarn install --frozen-lockfile`.
Legacy provider необходим и при сборке пакетов для production:

```sh
NODE_OPTIONS=--openssl-legacy-provider RAILS_ENV=production SECRET_KEY_BASE=<ключ> bundle exec rails webpacker:compile
```

Тесты бэкенда запускаются командой `DISABLE_SPRING=1 bundle exec rails test`.

- зарегистрируйтесь либо войдите;
- нажмите кнопку "Начать игру";
- перешлите ссылку другу;
- побеждайте;


## Built With

* Ruby - 3.0.1
* Rails - 6.0.3.4
* Vue - 2.6.12
* Node - 24

## Authors

* **Baidin Maxim** - *Creator* - [the_scrubs_fan](https://github.com/TheScrubsFan)

