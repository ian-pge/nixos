## Review
CLEAN

- Repeated Wi-Fi/Bluetooth show calls return before transition or hide logic (`StatusData.qml:695-699`, `StatusData.qml:808-812`).
- Rapid transitions capture opacity and offset for every mode before restarting (`Bar.qml:277-304`).
- Ordinary source/target cross-fade and offset choreography remains intact (`Bar.qml:246-275`).
- QML object tables use parenthesized bindings and whole-object reassignment (`Bar.qml:209-210`, `Bar.qml:298-299`).