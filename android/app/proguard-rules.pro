# Room creates its database implementation reflectively: it loads
# <DatabaseClass>_Impl by name and calls its no-argument constructor. R8 sees no
# caller for that constructor and removes it, so the class survives but cannot
# be instantiated.
#
# Nothing in CARTA uses Room directly. The Google Mobile Ads SDK pulls in
# WorkManager, whose androidx.startup initializer builds WorkDatabase before the
# first frame — which is why a release build crashed on launch with
# "Failed to create an instance of androidx.work.impl.WorkDatabase" while the
# debug build was fine.
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}

# Room's generated DAOs are reached the same way, from the kept implementation.
-keep class androidx.work.impl.** { *; }
-dontwarn androidx.work.**
