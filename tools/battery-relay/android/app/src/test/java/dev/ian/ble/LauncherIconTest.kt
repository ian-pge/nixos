package dev.ian.ble

import android.content.ComponentName
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.AdaptiveIconDrawable
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LauncherIconTest {
    @Test fun launcherAndApplicationAreNamedBleAndUseTheAdaptiveIcon() {
        val app = RuntimeEnvironment.getApplication()
        val pm = app.packageManager
        assertEquals("BLE", app.applicationInfo.loadLabel(pm).toString())
        assertEquals("BLE", pm.getActivityInfo(ComponentName(app, MainActivity::class.java), 0).loadLabel(pm).toString())
        assertEquals(R.mipmap.ic_launcher, app.applicationInfo.icon)
        assertTrue(app.getDrawable(R.mipmap.ic_launcher) is AdaptiveIconDrawable)
    }

    @Test fun fullColourAndThemedLogoRenderWithoutClipping() {
        val app = RuntimeEnvironment.getApplication()
        val icon = app.getDrawable(R.mipmap.ic_launcher) as AdaptiveIconDrawable
        assertNotNull(icon.monochrome)
        val output = File("build/reports/ui").apply { mkdirs() }
        val coloured = Bitmap.createBitmap(512, 512, Bitmap.Config.ARGB_8888)
        icon.setBounds(0, 0, 512, 512)
        icon.draw(Canvas(coloured))
        File(output, "app-icon.png").outputStream().use { coloured.compress(Bitmap.CompressFormat.PNG, 100, it) }
        coloured.recycle()
        // Check the complete silhouette at its source dimensions, independently
        // of a launcher's chosen mask or theme. No raster icon is shipped.
        val mask = requireNotNull(icon.monochrome)
        val bitmap = Bitmap.createBitmap(108, 108, Bitmap.Config.ARGB_8888)
        mask.setBounds(0, 0, 108, 108); mask.draw(Canvas(bitmap))
        var pixels = 0
        for (y in 0 until 108) for (x in 0 until 108) {
            if (Color.alpha(bitmap.getPixel(x, y)) > 16) {
                pixels++
                val dx = x + .5 - 54; val dy = y + .5 - 54
                assertTrue("Logo outside Android's safe circle: $x,$y", dx * dx + dy * dy <= 33 * 33)
            }
        }
        assertTrue(pixels > 800)
        assertEquals(0, Color.alpha(bitmap.getPixel(54, 50))) // Screen interior.
        assertEquals(255, Color.alpha(bitmap.getPixel(54, 34))) // Screen frame.
        assertEquals(255, Color.alpha(bitmap.getPixel(54, 71))) // Upright.
        assertEquals(255, Color.alpha(bitmap.getPixel(54, 78))) // Foot.
        assertEquals(0, Color.alpha(bitmap.getPixel(40, 73))) // Space beside the stand.
        File(output, "app-icon-monochrome.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }
}
