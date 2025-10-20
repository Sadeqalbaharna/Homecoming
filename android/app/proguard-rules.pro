# Keep AudioRecordingService and its methods
-keep class com.homecoming.app.AudioRecordingService { *; }
-keep class com.homecoming.app.AudioRecordingService$* { *; }

# Keep the service binder and its getService method
-keepclassmembers class * extends android.os.Binder {
    public <methods>;
}

# Don't obfuscate service classes
-keep public class * extends android.app.Service {
    public <methods>;
}

# Keep all methods in classes that extend Binder
-keepclassmembers class * {
    *** getService();
}
