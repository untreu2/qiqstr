package me.untreu.qiqstr.ui.auth

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.AppFont
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Prefs
import me.untreu.qiqstr.core.components.PrimaryButton
import me.untreu.qiqstr.core.components.SecondaryButton
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.data.accounts.AccountStore
import me.untreu.qiqstr.data.accounts.Ncryptsec
import me.untreu.qiqstr.data.accounts.Nip05Resolver
import me.untreu.qiqstr.data.bridge.Nip19
import me.untreu.qiqstr.data.sync.Session

enum class AuthStep { LOGIN, SIGNUP }

@Composable
fun AuthFlowScreen() {
    val path = remember { mutableStateListOf<AuthStep>() }
    BackHandler(enabled = path.isNotEmpty()) { path.removeAt(path.lastIndex) }
    AuthNavHost(path) {
        AuthWelcomeContent(onLogin = { path.add(AuthStep.LOGIN) }, onSignup = { path.add(AuthStep.SIGNUP) })
    }
}

@Composable
fun AuthNavHost(path: MutableList<AuthStep>, onBack: (() -> Unit)? = null, root: @Composable () -> Unit) {
    val top = path.lastOrNull()
    val depth = path.size
    AnimatedContent(
        targetState = top to depth,
        transitionSpec = {
            if (targetState.second > initialState.second) {
                (slideInHorizontally(tween(260)) { it / 3 } + fadeIn(tween(200))) togetherWith fadeOut(tween(160))
            } else {
                fadeIn(tween(200)) togetherWith (slideOutHorizontally(tween(260)) { it / 3 } + fadeOut(tween(200)))
            }
        },
        label = "auth-nav",
        modifier = Modifier.fillMaxSize().background(AppColors.background),
    ) { (step, _) ->
        val back = { if (path.isNotEmpty()) path.removeAt(path.lastIndex) else onBack?.invoke() }
        ScopedViewModels {
            when (step) {
                null -> root()
                AuthStep.LOGIN -> AuthLoginContent(onBack = { back() })
                AuthStep.SIGNUP -> AuthSignupContent(onBack = { back() })
            }
        }
    }
}

private class ScopedOwner(override val viewModelStore: ViewModelStore) : ViewModelStoreOwner

@Composable
fun ScopedViewModels(content: @Composable () -> Unit) {
    val owner = remember { ScopedOwner(ViewModelStore()) }
    DisposableEffect(owner) { onDispose { owner.viewModelStore.clear() } }
    CompositionLocalProvider(LocalViewModelStoreOwner provides owner, content = content)
}

private val boldWords = listOf("decentralized", "Nostr", "open source", "açık kaynaklı", "merkeziyetsiz", "dezentrales")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthWelcomeContent(isAddAccount: Boolean = false, onBack: (() -> Unit)? = null, onLogin: () -> Unit, onSignup: () -> Unit) {
    var acceptedTerms by remember { mutableStateOf(Prefs.bool("acceptedTerms")) }
    var pending by remember { mutableStateOf<AuthStep?>(null) }
    var showTermsPrompt by remember { mutableStateOf(false) }
    var showTerms by remember { mutableStateOf(false) }
    var showLanguage by remember { mutableStateOf(false) }
    val haptics = rememberHaptics()

    fun open(step: AuthStep) = if (step == AuthStep.SIGNUP) onSignup() else onLogin()
    fun accept() {
        acceptedTerms = true
        Prefs.set("acceptedTerms", true)
        haptics.success()
        val step = pending ?: return
        pending = null
        open(step)
    }
    fun proceed(step: AuthStep) {
        if (!acceptedTerms) {
            pending = step
            showTermsPrompt = true
            return
        }
        open(step)
    }

    Scaffold(
        containerColor = AppColors.background,
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {
                    if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) }
                },
                actions = {
                    IconButton(onClick = { showLanguage = true }, modifier = Modifier.testTag("welcome-language")) {
                        Icon(Icons.Outlined.Translate, L("language"))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
            )
        },
        bottomBar = {
            Column(
                Modifier.fillMaxWidth().background(AppColors.background).navigationBarsPadding().padding(start = 24.dp, end = 24.dp, top = 12.dp, bottom = 8.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                PrimaryButton(L("createNewAccount"), { proceed(AuthStep.SIGNUP) }, Modifier.fillMaxWidth().testTag("welcome-create-account"))
                SecondaryButton(L("welcomeAlreadyHaveAccount"), { proceed(AuthStep.LOGIN) }, Modifier.fillMaxWidth().testTag("welcome-login"))
            }
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
            Column(Modifier.padding(top = if (isAddAccount) 8.dp else 40.dp, start = 20.dp, end = 20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(L("welcomeTitle"), style = AppFont.brand(52.sp).copy(letterSpacing = (-1.5).sp), color = AppColors.textPrimary)
                Text(welcomeSubtitle(), style = MaterialTheme.typography.bodyLarge, color = AppColors.textSecondary)
            }
            Column(Modifier.padding(top = 36.dp, start = 24.dp, end = 24.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                AuthFeatureRow(Icons.Outlined.Public, L("welcomeFeatureDecentralized"))
                AuthFeatureRow(Icons.Outlined.Key, L("welcomeFeatureKeys"))
                AuthFeatureRow(Icons.Outlined.Lock, L("welcomeFeatureBitcoin"))
            }
        }
    }

    if (showTermsPrompt) {
        AlertDialog(
            onDismissRequest = { showTermsPrompt = false; pending = null },
            title = { Text(L("authTermsTitle")) },
            text = { Text(L("authTermsPromptMessage")) },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    TextAction(L("authTermsAgree"), { showTermsPrompt = false; accept() })
                    TextAction(L("authTermsRead"), { showTermsPrompt = false; showTerms = true })
                    TextAction(L("cancel"), { showTermsPrompt = false; pending = null })
                }
            },
        )
    }
    if (showTerms) {
        AuthTermsSheet(
            onAccept = if (pending == null) null else ({ showTerms = false; accept() }),
            onDismiss = {
                showTerms = false
                if (!acceptedTerms) pending = null
            },
        )
    }
    if (showLanguage) AuthLanguageSheet { showLanguage = false }
}

@Composable
private fun welcomeSubtitle() = buildAnnotatedString {
    val text = L("welcomeSubtitle")
    append(text)
    val primary = AppColors.textPrimary
    for (word in boldWords) {
        var index = text.indexOf(word)
        while (index >= 0) {
            addStyle(SpanStyle(fontWeight = FontWeight.Bold, color = primary), index, index + word.length)
            index = text.indexOf(word, index + word.length)
        }
    }
}

class AuthLoginViewModel : ViewModel() {
    var input by mutableStateOf("")
    var isObscured by mutableStateOf(true)
    var isLoading by mutableStateOf(false)
        private set
    var isDecrypting by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
    var password by mutableStateOf("")
    var passwordError by mutableStateOf<String?>(null)
    var failureCount by mutableIntStateOf(0)
        private set

    val isEncryptedInput: Boolean get() = Ncryptsec.matches(input)
    val canSubmit: Boolean get() = input.isNotBlank() && !isLoading && (!isEncryptedInput || password.isNotEmpty())
    val isViewOnlyInput: Boolean get() = AccountStore.readOnlyPubkey(input) != null || Nip05Resolver.looksLikeAddress(input)

    fun paste() {
        val text = SecureClipboard.paste() ?: return
        input = text
        errorMessage = null
    }

    fun applyScanned(value: String) {
        input = Nip19.stripScheme(value.trim())
        errorMessage = null
    }

    fun login() {
        if (!canSubmit) return
        val value = input.trim()
        isLoading = true
        errorMessage = null
        passwordError = null
        App.scope.launch {
            try {
                if (isEncryptedInput) {
                    isDecrypting = true
                    val key = try {
                        Ncryptsec.decrypt(value, password)
                    } catch (error: Throwable) {
                        passwordError = coreErrorMessage(error)
                        failureCount += 1
                        return@launch
                    }
                    isDecrypting = false
                    password = ""
                    Session.login(key)
                } else {
                    Session.login(value)
                }
            } catch (error: Throwable) {
                errorMessage = L("errorPrefix", "message" to coreErrorMessage(error))
                failureCount += 1
            } finally {
                isLoading = false
                isDecrypting = false
            }
        }
    }
}

@Composable
fun AuthTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    secure: Boolean = false,
    singleLine: Boolean = true,
    keyboardType: KeyboardType = KeyboardType.Text,
    imeAction: ImeAction = ImeAction.Default,
    onSubmit: (() -> Unit)? = null,
    enabled: Boolean = true,
    trailing: (@Composable () -> Unit)? = null,
) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder) },
        singleLine = singleLine,
        enabled = enabled,
        visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(
            keyboardType = if (secure) KeyboardType.Password else keyboardType,
            imeAction = imeAction,
            autoCorrectEnabled = false,
        ),
        keyboardActions = KeyboardActions(onAny = { onSubmit?.invoke() }),
        trailingIcon = trailing,
        shape = RoundedCornerShape(14.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = AppColors.inputFill,
            unfocusedContainerColor = AppColors.inputFill,
            disabledContainerColor = AppColors.inputFill,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
        ),
        modifier = modifier.fillMaxWidth(),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthLoginContent(onBack: () -> Unit) {
    val model: AuthLoginViewModel = viewModel()
    val focus = LocalFocusManager.current
    val passwordFocus = remember { FocusRequester() }
    val haptics = rememberHaptics()
    val scan = rememberQrScanner { model.applyScanned(it) }
    var previousLength by remember { mutableIntStateOf(model.input.length) }
    LaunchedEffect(model.failureCount) { if (model.failureCount > 0) haptics.error() }
    LaunchedEffect(model.input) {
        if (model.isEncryptedInput && model.input.length - previousLength > 1) runCatching { passwordFocus.requestFocus() }
        previousLength = model.input.length
    }
    LaunchedEffect(model.password) { model.passwordError = null }
    val submit = {
        focus.clearFocus()
        model.login()
    }
    Scaffold(
        containerColor = AppColors.background,
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = { IconButton(onClick = onBack, enabled = !model.isLoading) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
                actions = {
                    IconButton(onClick = scan, enabled = !model.isLoading, modifier = Modifier.testTag("login-scan")) {
                        Icon(Icons.Outlined.QrCodeScanner, L("scanQRCode"))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
            )
        },
        bottomBar = {
            Box(Modifier.fillMaxWidth().background(AppColors.background).navigationBarsPadding().imePadding().padding(horizontal = 24.dp, vertical = 8.dp)) {
                PrimaryButton(L("login"), { submit() }, Modifier.fillMaxWidth().testTag("login-submit"), enabled = model.canSubmit, loading = model.isLoading)
            }
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            AuthHeader(L("login"), L("loginSubtitle"))
            Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
                AuthTextField(
                    value = model.input,
                    onValueChange = { model.input = it },
                    placeholder = L("authLoginPlaceholder"),
                    secure = model.isObscured,
                    imeAction = ImeAction.Go,
                    onSubmit = { submit() },
                    enabled = !model.isLoading,
                    modifier = Modifier.testTag("login-input"),
                    trailing = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            IconButton(onClick = { model.isObscured = !model.isObscured }, modifier = Modifier.testTag("login-toggle-visibility")) {
                                Icon(
                                    if (model.isObscured) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                                    if (model.isObscured) L("showKey") else L("hideKey"),
                                    tint = AppColors.textSecondary,
                                )
                            }
                            FilledIconButton(
                                onClick = { model.paste() },
                                shape = CircleShape,
                                colors = IconButtonDefaults.filledIconButtonColors(containerColor = AppColors.textPrimary, contentColor = AppColors.background),
                                modifier = Modifier.padding(end = 6.dp).size(34.dp).testTag("login-paste"),
                            ) { Icon(Icons.Outlined.ContentPaste, L("authPaste"), Modifier.size(18.dp)) }
                        }
                    },
                )
                AnimatedVisibility(model.errorMessage != null, enter = fadeIn(), exit = fadeOut()) {
                    model.errorMessage?.let { AuthErrorText(it) }
                }
                AnimatedVisibility(model.isEncryptedInput, enter = fadeIn(), exit = fadeOut()) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        HintLabel(Icons.Outlined.Lock, L("authNcryptsecDetected"))
                        AuthTextField(
                            value = model.password,
                            onValueChange = { model.password = it },
                            placeholder = L("authNcryptsecPassword"),
                            secure = true,
                            imeAction = ImeAction.Go,
                            onSubmit = { submit() },
                            enabled = !model.isLoading,
                            modifier = Modifier.focusRequester(passwordFocus).testTag("login-ncryptsec-password"),
                        )
                        model.passwordError?.let { AuthErrorText(it, tag = "login-ncryptsec-error") }
                        if (model.isDecrypting) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(horizontal = 4.dp)) {
                                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = AppColors.textSecondary)
                                Text(L("authDecrypting"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
                            }
                        }
                    }
                }
                AnimatedVisibility(model.isViewOnlyInput, enter = fadeIn(), exit = fadeOut()) {
                    HintLabel(Icons.Outlined.Visibility, L("readOnlyLoginHint"), Modifier.testTag("login-view-only-hint"))
                }
                Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("loginExampleSeed", "loginExampleNsec", "loginExampleViewOnly").forEach {
                        Text(L(it), style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
                    }
                }
            }
        }
    }
}

@Composable
fun HintLabel(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, modifier: Modifier = Modifier) {
    Row(modifier.padding(horizontal = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, Modifier.size(18.dp), tint = AppColors.textSecondary)
        Text(text, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
    }
}

class AuthSignupViewModel : ViewModel() {
    var isLoading by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set
    var failureCount by mutableIntStateOf(0)
        private set

    fun create() {
        if (isLoading) return
        isLoading = true
        errorMessage = null
        App.scope.launch {
            try {
                Session.createAccount()
            } catch (error: Throwable) {
                errorMessage = L("errorPrefix", "message" to coreErrorMessage(error))
                failureCount += 1
            }
            isLoading = false
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthSignupContent(onBack: () -> Unit) {
    val model: AuthSignupViewModel = viewModel()
    val haptics = rememberHaptics()
    LaunchedEffect(model.failureCount) { if (model.failureCount > 0) haptics.error() }
    BackHandler(enabled = model.isLoading) {}
    Box(Modifier.fillMaxSize()) {
        Scaffold(
            containerColor = AppColors.background,
            topBar = {
                TopAppBar(
                    title = {},
                    navigationIcon = { if (!model.isLoading) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
                )
            },
            bottomBar = {
                Box(Modifier.fillMaxWidth().background(AppColors.background).navigationBarsPadding().padding(horizontal = 24.dp, vertical = 8.dp)) {
                    PrimaryButton(L("createNewAccount"), { model.create() }, Modifier.fillMaxWidth().testTag("signup-create"), loading = model.isLoading)
                }
            },
        ) { padding ->
            Column(
                Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp),
                verticalArrangement = Arrangement.spacedBy(32.dp),
            ) {
                AuthHeader(L("createNewAccount"), L("signupSubtitle"))
                Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                    AuthFeatureRow(Icons.Outlined.Key, L("signupFeatureKeys"))
                    AuthFeatureRow(Icons.Outlined.VerifiedUser, L("signupFeatureBackup"))
                    AuthFeatureRow(Icons.Outlined.Person, L("signupFeatureProfile"))
                }
                AnimatedVisibility(model.errorMessage != null) { model.errorMessage?.let { AuthErrorText(it) } }
            }
        }
        AnimatedVisibility(model.isLoading, enter = fadeIn(), exit = fadeOut()) {
            Column(
                Modifier.fillMaxSize().background(AppColors.background).testTag("signup-creating"),
                verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CircularProgressIndicator(color = AppColors.textPrimary)
                Text(L("signupCreating"), style = MaterialTheme.typography.bodyLarge, color = AppColors.textSecondary)
            }
        }
    }
}
