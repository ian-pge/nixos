package dev.ian.ble

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.view.Gravity
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.widget.Button
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.min

/** A small native design system, using the same Macchiato palette as the desktop. */
object RelayUi {
    val CRUST = Color.rgb(24, 25, 38)
    val BASE = Color.rgb(36, 39, 58)
    val SURFACE = Color.rgb(54, 58, 79)
    val TEXT = Color.rgb(202, 211, 245)
    val MUTED = Color.rgb(165, 173, 203)
    val YELLOW = Color.rgb(238, 212, 159)
    val GREEN = Color.rgb(166, 218, 149)
    val MAUVE = Color.rgb(198, 160, 246)
    val RED = Color.rgb(237, 135, 150)

    fun Context.dp(value: Int) = (value * resources.displayMetrics.density + .5f).toInt()
    fun background(context: Context, color: Int = BASE, radius: Int = 26, border: Boolean = false) = GradientDrawable().apply {
        setColor(color); cornerRadius = context.dp(radius).toFloat()
        if (border) setStroke(context.dp(1), SURFACE)
    }
    fun text(context: Context, value: String, size: Float = 14f, color: Int = TEXT, bold: Boolean = false) = TextView(context).apply {
        text = value; textSize = size; setTextColor(color)
        typeface = Typeface.create(if (bold) "sans-serif-medium" else "sans-serif", Typeface.NORMAL)
        setLineSpacing(context.dp(3).toFloat(), 1f)
        includeFontPadding = false
    }
    fun column(context: Context, gapBottom: Int = 0) = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        layoutParams = LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = context.dp(gapBottom) }
    }
    fun card(context: Context) = column(context, 16).apply {
        setPadding(context.dp(22), context.dp(22), context.dp(22), context.dp(22))
        background = background(context, BASE, 28, true)
    }
    fun space(context: Context, height: Int) = View(context).apply { layoutParams = LinearLayout.LayoutParams(1, context.dp(height)) }
    fun button(context: Context, value: String, accent: Int = YELLOW, secondary: Boolean = false, action: () -> Unit) = Button(context).apply {
        text = value; textSize = 14f; isAllCaps = false
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        val states = arrayOf(intArrayOf(-android.R.attr.state_enabled), intArrayOf())
        setTextColor(ColorStateList(states, intArrayOf(MUTED, if (secondary) accent else CRUST)))
        val fill = if (secondary) SURFACE else accent
        val shapes = android.graphics.drawable.StateListDrawable().apply {
            addState(intArrayOf(-android.R.attr.state_enabled), background(context, SURFACE, 18))
            addState(intArrayOf(), background(context, fill, 18))
        }
        background = RippleDrawable(ColorStateList.valueOf(0x22ffffff), shapes, null)
        minHeight = context.dp(52); minimumHeight = context.dp(52)
        setPadding(context.dp(16), context.dp(12), context.dp(16), context.dp(12))
        setOnClickListener { action() }
        stateListAnimator = null
        layoutParams = LinearLayout.LayoutParams(-1, -2)
    }
    fun icon(context: Context, name: String, color: Int = YELLOW, size: Int = 24) = ImageView(context).apply {
        setImageDrawable(RelayGlyph(name, color))
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        layoutParams = LinearLayout.LayoutParams(context.dp(size), context.dp(size))
    }
    fun iconButton(context: Context, name: String, description: String, action: () -> Unit) = ImageButton(context).apply {
        setImageDrawable(RelayGlyph(name, TEXT)); contentDescription = description
        setPadding(context.dp(13), context.dp(13), context.dp(13), context.dp(13))
        background = RippleDrawable(ColorStateList.valueOf(0x22ffffff), background(context, SURFACE, 16), null)
        layoutParams = LinearLayout.LayoutParams(context.dp(48), context.dp(48))
        setOnClickListener { action() }
    }
    fun row(context: Context) = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
}

/** Simple scalable line icons, not text glyphs dependent on the installed font. */
class RelayGlyph(private val name: String, private val tint: Int) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeWidth = 1.7f; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    override fun draw(canvas: Canvas) {
        val saved = canvas.save()
        canvas.translate(bounds.left.toFloat(), bounds.top.toFloat())
        canvas.scale(bounds.width() / 24f, bounds.height() / 24f)
        paint.color = tint
        fun line(vararg xy: Float) { val path = Path(); path.moveTo(xy[0], xy[1]); for (i in 2 until xy.size step 2) path.lineTo(xy[i], xy[i + 1]); canvas.drawPath(path, paint) }
        when (name) {
            "phone" -> { canvas.drawRoundRect(6f, 2f, 18f, 22f, 3f, 3f, paint); line(10f, 18.5f, 14f, 18.5f) }
            "watch" -> { canvas.drawRoundRect(6f, 6f, 18f, 18f, 4f, 4f, paint); line(9f, 6f, 9f, 2f, 15f, 2f, 15f, 6f); line(9f, 18f, 9f, 22f, 15f, 22f, 15f, 18f); line(12f, 9f, 12f, 12f, 14f, 13f) }
            "headphones" -> { canvas.drawArc(RectF(3f, 3f, 21f, 21f), 180f, 180f, false, paint); canvas.drawRoundRect(3f, 11f, 7f, 20f, 2f, 2f, paint); canvas.drawRoundRect(17f, 11f, 21f, 20f, 2f, 2f, paint) }
            "monitor" -> { canvas.drawRoundRect(2f, 3f, 22f, 17f, 2f, 2f, paint); line(12f, 17f, 12f, 21f); line(8f, 21f, 16f, 21f) }
            "back" -> { line(15f, 5f, 8f, 12f, 15f, 19f) }
            "chevron" -> { line(9f, 6f, 15f, 12f, 9f, 18f) }
            "refresh" -> { canvas.drawArc(RectF(4f, 4f, 20f, 20f), 30f, 290f, false, paint); line(20f, 4f, 20f, 10f, 14f, 10f) }
            "copy" -> { canvas.drawRoundRect(8f, 8f, 21f, 21f, 2f, 2f, paint); line(16f, 4f, 16f, 2f, 3f, 2f, 3f, 16f, 5f, 16f) }
            "bolt" -> { line(13f, 2f, 5f, 13f, 11f, 13f, 10f, 22f, 19f, 10f, 13f, 10f, 13f, 2f) }
            "shield" -> { line(12f, 2f, 21f, 6f, 20f, 14f, 17f, 19f, 12f, 22f, 7f, 19f, 4f, 14f, 3f, 6f, 12f, 2f); line(8f, 12f, 11f, 15f, 16f, 9f) }
            "settings" -> { line(3f, 6f, 8f, 6f); line(14f, 6f, 21f, 6f); canvas.drawCircle(11f, 6f, 3f, paint); line(3f, 17f, 12f, 17f); line(18f, 17f, 21f, 17f); canvas.drawCircle(15f, 17f, 3f, paint) }
            else -> { canvas.drawCircle(12f, 12f, 9f, paint); line(12f, 8f, 12f, 13f); line(12f, 17f, 12f, 17.1f) }
        }
        canvas.restoreToCount(saved)
    }
    override fun setAlpha(alpha: Int) { paint.alpha = alpha; invalidateSelf() }
    override fun setColorFilter(colorFilter: ColorFilter?) { paint.colorFilter = colorFilter; invalidateSelf() }
    @Deprecated("Deprecated in Android") override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}

class BatteryGauge(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val ring = RectF()
    private val numberTypeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    private val labelTypeface = Typeface.create("sans-serif", Typeface.NORMAL)
    private var value: Int? = null
    private var amount = 0f
    private var accent = RelayUi.YELLOW
    private var animation: ValueAnimator? = null
    fun setBattery(percent: Int?, color: Int) {
        accent = color
        if (value != percent) {
            value = percent; animation?.cancel()
            val target = (percent ?: 0) / 100f
            if (isLaidOut && ValueAnimator.areAnimatorsEnabled()) {
                animation = ValueAnimator.ofFloat(amount, target).apply {
                    duration = 220; interpolator = DecelerateInterpolator()
                    addUpdateListener { amount = it.animatedValue as Float; invalidate() }; start()
                }
            } else amount = target
        }
        contentDescription = percent?.let { "Batterie : $it pour cent" } ?: "Batterie inconnue"
        invalidate()
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val size = min(width, height).toFloat()
        val cx = width / 2f; val cy = height / 2f
        val stroke = size * .055f; val radius = size / 2 - stroke
        ring.set(cx - radius, cy - radius, cx + radius, cy + radius)
        paint.style = Paint.Style.STROKE; paint.strokeWidth = stroke; paint.strokeCap = Paint.Cap.ROUND
        paint.color = RelayUi.SURFACE; canvas.drawCircle(cx, cy, radius, paint)
        if (value != null && amount > 0) { paint.color = accent; canvas.drawArc(ring, -90f, 360f * amount, false, paint) }
        paint.style = Paint.Style.FILL; paint.color = RelayUi.TEXT; paint.textAlign = Paint.Align.CENTER
        paint.typeface = numberTypeface; paint.textSize = size * .25f
        canvas.drawText(value?.let { "$it%" } ?: "—", cx, cy + size * .025f, paint)
        paint.color = RelayUi.MUTED; paint.typeface = labelTypeface; paint.textSize = size * .075f
        canvas.drawText("BATTERIE", cx, cy + size * .17f, paint)
    }
    override fun onDetachedFromWindow() { animation?.cancel(); super.onDetachedFromWindow() }
}
