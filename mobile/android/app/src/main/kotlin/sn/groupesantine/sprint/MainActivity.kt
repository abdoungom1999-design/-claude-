package sn.groupesantine.sprint

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Alertes sonores (canal "sprint/alerte", appelé par
 * lib/core/alertes/alerte_sonore_natif.dart) : son de notification du
 * téléphone et vibrations. "nouvelleCourse" (chauffeur) : trois vibrations
 * longues ; "nouveauMessage" (client) : deux vibrations courtes.
 * L'équivalent web passe par Web Audio.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        creerCanauxDeNotification()
    }

    /**
     * Canaux des notifications push (Android 8+), créés à chaque démarrage
     * (sans effet s'ils existent déjà) donc avant toute notification : le
     * serveur les désigne par leur identifiant (functions/src/notifications.ts).
     * Importance haute : son, vibration et affichage sur l'écran verrouillé.
     */
    private fun creerCanauxDeNotification() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val gestionnaire = getSystemService(NotificationManager::class.java) ?: return
            val messages = NotificationChannel("messages", "Messages", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Messages de votre chauffeur ou de votre client"
                enableVibration(true)
            }
            val courses = NotificationChannel("courses", "Courses", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Nouvelles courses, chauffeur trouvé, annulations"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 400, 200, 400)
            }
            gestionnaire.createNotificationChannel(messages)
            gestionnaire.createNotificationChannel(courses)
        } catch (e: Exception) {
            // Notifications indisponibles : l'app fonctionne sans.
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sprint/alerte")
            .setMethodCallHandler { appel, resultat ->
                when (appel.method) {
                    "nouvelleCourse" -> {
                        sonner()
                        vibrer(longArrayOf(0, 400, 200, 400, 200, 400))
                        resultat.success(null)
                    }
                    "nouveauMessage" -> {
                        sonner()
                        vibrer(longArrayOf(0, 200, 100, 200))
                        resultat.success(null)
                    }
                    else -> resultat.notImplemented()
                }
            }
    }

    private fun sonner() {
        try {
            val son = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            RingtoneManager.getRingtone(applicationContext, son)?.play()
        } catch (e: Exception) {
            // Pas de son disponible : la vibration suffit.
        }
    }

    private fun vibrer(motif: LongArray) {
        try {
            val vibreur: Vibrator =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibreur.vibrate(VibrationEffect.createWaveform(motif, -1))
            } else {
                @Suppress("DEPRECATION")
                vibreur.vibrate(motif, -1)
            }
        } catch (e: Exception) {
            // Téléphone sans vibreur.
        }
    }
}
