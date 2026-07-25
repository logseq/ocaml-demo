package ocaml.demo

import android.app.Application
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import skip.foundation.ProcessInfo
import skip.ui.ColorScheme
import skip.ui.ComposeContext
import skip.ui.PresentationRoot

class AndroidAppMain : Application() {
    override fun onCreate() {
        super.onCreate()
        ProcessInfo.launch(applicationContext)
    }
}

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        skip.ui.UIApplication.launch(this)
        enableEdgeToEdge()
        setContent {
            PresentationRootView(ComposeContext())
        }
    }
}

@Composable
private fun PresentationRootView(context: ComposeContext) {
    val colorScheme =
        if (androidx.compose.foundation.isSystemInDarkTheme()) {
            ColorScheme.dark
        } else {
            ColorScheme.light
        }
    PresentationRoot(defaultColorScheme = colorScheme, context = context) { rootContext ->
        val contentContext = rootContext.content()
        Box(
            modifier = rootContext.modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            OCamlDemoAppView().Compose(context = contentContext)
        }
    }
}
