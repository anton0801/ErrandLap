# Ответ на Guideline 2.1 — Information Needed

Отказ не по функциональности. Apple просит данные в **App Store Connect →
App Review Information → Notes** плюс видео. Ниже готовый текст на английском —
вставить в Notes целиком, заменив три места, помеченные `<< >>`.

**Что нужно от вас до отправки:**

1. **Запись экрана с реального iPhone** — это единственное, что нельзя обойти.
   Apple прямо пишет «captured on a physical device». Симулятор не подойдёт.
   Сценарий записи — в конце файла.
2. Вписать в текст модель айфона и версию iOS, на котором делали запись.
3. Проверить в App Store Connect раздел **App Privacy**: для этой сборки
   должно стоять **Data Not Collected**. Приложение действительно ничего не
   собирает и никуда не отправляет, и если там указано иное — будет отказ уже
   по другому пункту.

---

## Текст для поля Notes (вставить как есть)

```
ABOUT THIS APP

Errand Run is an offline planner for everyday errands — pharmacy, post office,
bank, clinic, shops, paperwork.

The problem it solves: a to-do list does not know that the post office closes at
14:00 and is twenty minutes away, and a map app does not know you only have
ninety minutes between work and school pickup. Neither answers the question the
user actually has, which is "what from my list can I realistically finish today?"

The user enters their errands, the places those errands happen at (with opening
hours, lunch breaks and last-entry times), and the free windows they actually
have. The app then builds a route that fits inside that window, counting travel
time, time inside each place and a buffer for parking. Anything that does not fit
is not dropped — it is moved to the next window where it does fit, and the app
says when that window is.

The app deliberately never predicts queue length. It asks the user for their own
estimate, records how long a visit actually took, and after a few visits plans
with the user's own measured average for that place.

TARGET AUDIENCE: adults running household errands. General audience, no age
restriction, no user-generated content shared with anyone.

1. SCREEN RECORDING

Attached / provided at the link below. Recorded on a physical device running the
current iOS release. It starts from launching the app and shows the full flow:
onboarding, initial setup, adding a place with opening hours, adding an errand,
adding a free window, building a route, running it, and recording how long it
actually took. The one permission prompt in the app (local notifications) is
shown being requested in Settings.

2. DEVICES AND OS TESTED ON

- << iPhone model >>, iOS << version >> (physical device)
- iOS Simulator: iPhone 16, iPhone 16 Pro, iPad, iOS 18.5

3. FUNCTIONS AND VALUE

See ABOUT THIS APP above. Core features:
- Errands with duration, deadline, priority, required documents, dependencies
- Places with per-weekday opening hours, lunch breaks, last-entry time, parking
  difficulty and the user's own queue estimate
- Free windows that start and end at real points (left work, must be at school)
- A route builder that explains in plain sentences why each stop fits or does not
- A live run mode that records what actually happened
- A "wasted trip" log for when a place was unexpectedly closed
- Personal statistics: estimates versus reality, per place

4. HOW TO SET UP AND REACH THE MAIN FEATURES

NO LOGIN IS REQUIRED. This version of the app has no accounts, no registration
and no sign-in. There is nothing to log into and no demo credentials are needed.
No sample files are needed either.

To reach the core feature in about a minute from a fresh install:
  1. Onboarding: tap "Next" three times, then "Set Up and Start".
  2. Initial setup: enter any home address, pick a travel mode, tap "Save Setup".
     (Only these two fields are required.)
  3. Places tab -> "Add a Place": enter a name and address, set opening hours,
     save.
  4. Errands tab -> "Add an Errand": enter a title, pick the place created above,
     set how long it takes, save.
  5. Settings (gear icon, top right of Today) -> Windows -> add a free window
     with a start and end time.
  6. Today tab: the route is built automatically and each stop is explained.
     "Why This Order" explains the ordering. Starting the run opens the live
     run mode.

5. EXTERNAL SERVICES, TOOLS AND PLATFORMS

None, other than Apple's own frameworks on the device:

- Apple MapKit and CoreLocation geocoding (MKDirections, CLGeocoder) are used for
  exactly one thing: turning an address the user typed into a point, and getting
  the travel time between two of those points. This is requested by the device
  from Apple. It is optional — if it is unavailable, the app says so and lets the
  user type travel times by hand, and every other feature keeps working.
- Local notifications (UNUserNotificationCenter), scheduled on the device.

There is NO backend server, NO account system, NO analytics, NO advertising, NO
tracking, NO third-party SDK, NO payment processor, NO subscription, NO AI or
machine-learning service, and NO data provider. The app makes no network requests
of its own. All user data is stored in the app's own container on the device.

The app never requests location access — there is no CLLocationManager in the
app and no location permission prompt. The only permission it ever asks for is
local notifications, and only when the user switches reminders on in Settings.
Photos can optionally be attached to a place through the system photo picker,
which does not require photo library access.

6. REGIONAL DIFFERENCES

None. The app behaves identically in every region and in every country. There is
no region gating, no regionally different content, no regional pricing and no
regionally restricted feature. The interface is English only. Times are shown in
the device's own format and the app uses the device's calendar and time zone.
Apple's map service coverage varies by country, but the app does not depend on
it: travel times can always be entered by hand.

7. REGULATED INDUSTRY OR THIRD-PARTY MATERIAL

Not applicable. The app is not in a regulated industry — it is a personal
planning tool. It provides no medical, financial, legal or professional advice,
and makes no claims of any kind about the businesses a user enters as places;
those entries are typed by the user and stored only on their own device.

It contains no third-party or protected material. All text, icons, graphics and
code are original. Typography uses the system font. There are no third-party
trademarks, no licensed content and no external databases.

CONTACT

<< support email >>
```

---

## Сценарий записи экрана

Записывать на реальном iPhone (Настройки → Пункт управления → Запись экрана).
Целиком одним дублем, примерно 2–3 минуты, начиная **с запуска приложения** —
Apple это требует явно. Перед записью лучше удалить приложение и поставить
заново, чтобы был чистый первый запуск.

1. **Домашний экран → тап по иконке.** Не начинайте с уже открытого приложения.
2. **Онбординг** — пролистать все четыре экрана, нажать «Set Up and Start».
3. **Первичная настройка** — вписать адрес дома, выбрать способ передвижения,
   «Save Setup».
4. **Places → Add a Place** — название, адрес, часы работы (показать, что
   выставляются по дням и есть обед), сохранить.
5. **Errands → Add an Errand** — название, выбрать созданное место,
   длительность, сохранить.
6. **Настройки (шестерёнка) → Windows** — добавить окно с началом и концом.
7. **Today** — показать собранный маршрут и объяснения, нажать «Why This Order».
8. **Запустить маршрут** — тёмный режим, отметить «Arrived», «Done», вписать
   фактическое время.
9. **Настройки → Notifications** — включить тумблер, чтобы **в кадре появился
   системный запрос разрешения на уведомления**. Это отдельный пункт запроса.
10. **Настройки → Your Data** — показать экран, где написано, что всё хранится
    на телефоне.
11. **Настройки → Data → Export Data** — показать выгрузку.

Чего в записи быть **не должно**, потому что этого нет в сборке: регистрации,
входа, удаления аккаунта, покупок, подписок, пользовательского контента,
запросов геолокации, камеры или App Tracking Transparency. В тексте Notes это
сказано прямо, чтобы у ревьюера не осталось вопроса «а где это».

---

## Когда включите сервер

В апдейте с `.connected` придётся дописать в Notes:
- демо-аккаунт (почта и пароль) в полях Sign-In Information,
- в пункт 1 добавить регистрацию, вход и удаление аккаунта в записи,
- в пункте 5 указать собственный сервер как внешний сервис,
- в App Privacy заменить «Data Not Collected» на реальные категории
  (Contact Info → Email, User Content),
- поставить `APP_MODE=connected` на сервере, чтобы страницы описывали аккаунты.
