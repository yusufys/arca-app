package app.arca.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import app.arca.android.ui.ArcaRootApp
import app.arca.android.ui.ArcaViewModel

class MainActivity : ComponentActivity() {
    private val viewModel: ArcaViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            ArcaRootApp(viewModel = viewModel)
        }
    }
}
