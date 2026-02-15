import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('tr')
  ];

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your app preferences.'**
  String get settingsSubtitle;

  /// No description provided for @relays.
  ///
  /// In en, this message translates to:
  /// **'Relays'**
  String get relays;

  /// No description provided for @yourDataOnRelays.
  ///
  /// In en, this message translates to:
  /// **'Your Data on Relays'**
  String get yourDataOnRelays;

  /// No description provided for @keys.
  ///
  /// In en, this message translates to:
  /// **'Keys'**
  String get keys;

  /// No description provided for @display.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get display;

  /// No description provided for @payments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get payments;

  /// No description provided for @muted.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get muted;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select your preferred language'**
  String get languageSubtitle;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @turkish.
  ///
  /// In en, this message translates to:
  /// **'Turkish'**
  String get turkish;

  /// No description provided for @german.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get german;

  /// No description provided for @failedToUploadEncryptedMedia.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload encrypted media'**
  String get failedToUploadEncryptedMedia;

  /// No description provided for @noMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noMessagesYet;

  /// No description provided for @failedToDecryptMedia.
  ///
  /// In en, this message translates to:
  /// **'Failed to decrypt media'**
  String get failedToDecryptMedia;

  /// No description provided for @legacyUnencryptedMedia.
  ///
  /// In en, this message translates to:
  /// **'Legacy unencrypted media'**
  String get legacyUnencryptedMedia;

  /// No description provided for @decryptionError.
  ///
  /// In en, this message translates to:
  /// **'Decryption Error'**
  String get decryptionError;

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknownError;

  /// No description provided for @decryptionFailed.
  ///
  /// In en, this message translates to:
  /// **'Decryption failed'**
  String get decryptionFailed;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @errorSelectingMedia.
  ///
  /// In en, this message translates to:
  /// **'Error selecting media'**
  String get errorSelectingMedia;

  /// No description provided for @errorSelectingUser.
  ///
  /// In en, this message translates to:
  /// **'Error selecting user'**
  String get errorSelectingUser;

  /// No description provided for @errorSharingNote.
  ///
  /// In en, this message translates to:
  /// **'Error sharing note'**
  String get errorSharingNote;

  /// No description provided for @emptyNoteMessage.
  ///
  /// In en, this message translates to:
  /// **'Please enter a note or add media'**
  String get emptyNoteMessage;

  /// No description provided for @addMediaText.
  ///
  /// In en, this message translates to:
  /// **'Add media'**
  String get addMediaText;

  /// No description provided for @retryText.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryText;

  /// No description provided for @hintText.
  ///
  /// In en, this message translates to:
  /// **'What\'s on your mind?'**
  String get hintText;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @uploadingMediaFiles.
  ///
  /// In en, this message translates to:
  /// **'Uploading media files'**
  String get uploadingMediaFiles;

  /// No description provided for @addMediaFilesToPost.
  ///
  /// In en, this message translates to:
  /// **'Add media files to your post'**
  String get addMediaFilesToPost;

  /// No description provided for @addGifFromGiphy.
  ///
  /// In en, this message translates to:
  /// **'Add GIF from Giphy'**
  String get addGifFromGiphy;

  /// No description provided for @postYourNote.
  ///
  /// In en, this message translates to:
  /// **'Post your note'**
  String get postYourNote;

  /// No description provided for @composeYourNote.
  ///
  /// In en, this message translates to:
  /// **'Compose your note'**
  String get composeYourNote;

  /// No description provided for @removeThisMediaFile.
  ///
  /// In en, this message translates to:
  /// **'Remove this media file'**
  String get removeThisMediaFile;

  /// No description provided for @yourFeedIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your feed is empty'**
  String get yourFeedIsEmpty;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @reads.
  ///
  /// In en, this message translates to:
  /// **'Reads'**
  String get reads;

  /// No description provided for @noArticlesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No articles available'**
  String get noArticlesAvailable;

  /// No description provided for @searchError.
  ///
  /// In en, this message translates to:
  /// **'Search Error'**
  String get searchError;

  /// No description provided for @noResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResultsFound;

  /// No description provided for @users.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get users;

  /// No description provided for @following.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get following;

  /// No description provided for @follow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get follow;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @createNewAccount.
  ///
  /// In en, this message translates to:
  /// **'Create a New Account'**
  String get createNewAccount;

  /// No description provided for @noFollowingUsers.
  ///
  /// In en, this message translates to:
  /// **'No following users'**
  String get noFollowingUsers;

  /// No description provided for @unknownUser.
  ///
  /// In en, this message translates to:
  /// **'Unknown User'**
  String get unknownUser;

  /// No description provided for @failedToLoadSuggestedUsers.
  ///
  /// In en, this message translates to:
  /// **'Failed to load suggested users'**
  String get failedToLoadSuggestedUsers;

  /// No description provided for @suggestedFollows.
  ///
  /// In en, this message translates to:
  /// **'Suggested Follows'**
  String get suggestedFollows;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @noEventsToRebroadcast.
  ///
  /// In en, this message translates to:
  /// **'No events to rebroadcast'**
  String get noEventsToRebroadcast;

  /// No description provided for @errorRebroadcastingEvents.
  ///
  /// In en, this message translates to:
  /// **'Error rebroadcasting events'**
  String get errorRebroadcastingEvents;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @noEventsFoundToDelete.
  ///
  /// In en, this message translates to:
  /// **'No events found to delete'**
  String get noEventsFoundToDelete;

  /// No description provided for @noValidEventIdsFound.
  ///
  /// In en, this message translates to:
  /// **'No valid event IDs found'**
  String get noValidEventIdsFound;

  /// No description provided for @userRequestedAccountDeletion.
  ///
  /// In en, this message translates to:
  /// **'User requested account deletion'**
  String get userRequestedAccountDeletion;

  /// No description provided for @profileMetadata.
  ///
  /// In en, this message translates to:
  /// **'Profile Metadata'**
  String get profileMetadata;

  /// No description provided for @textNote.
  ///
  /// In en, this message translates to:
  /// **'Text Note'**
  String get textNote;

  /// No description provided for @follows.
  ///
  /// In en, this message translates to:
  /// **'Follows'**
  String get follows;

  /// No description provided for @encryptedDirectMessage.
  ///
  /// In en, this message translates to:
  /// **'Encrypted Direct Message'**
  String get encryptedDirectMessage;

  /// No description provided for @eventDeletion.
  ///
  /// In en, this message translates to:
  /// **'Event Deletion'**
  String get eventDeletion;

  /// No description provided for @repost.
  ///
  /// In en, this message translates to:
  /// **'Repost'**
  String get repost;

  /// No description provided for @reaction.
  ///
  /// In en, this message translates to:
  /// **'Reaction'**
  String get reaction;

  /// No description provided for @muteList.
  ///
  /// In en, this message translates to:
  /// **'Mute List'**
  String get muteList;

  /// No description provided for @relayList.
  ///
  /// In en, this message translates to:
  /// **'Relay List'**
  String get relayList;

  /// No description provided for @rebroadcasting.
  ///
  /// In en, this message translates to:
  /// **'Rebroadcasting...'**
  String get rebroadcasting;

  /// No description provided for @rebroadcast.
  ///
  /// In en, this message translates to:
  /// **'Rebroadcast'**
  String get rebroadcast;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @banner.
  ///
  /// In en, this message translates to:
  /// **'Banner'**
  String get banner;

  /// No description provided for @profileImage.
  ///
  /// In en, this message translates to:
  /// **'Profile image'**
  String get profileImage;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @pleaseEnterValidWebsiteUrl.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid website URL'**
  String get pleaseEnterValidWebsiteUrl;

  /// No description provided for @setUpProfile.
  ///
  /// In en, this message translates to:
  /// **'Set Up Profile'**
  String get setUpProfile;

  /// No description provided for @thread.
  ///
  /// In en, this message translates to:
  /// **'Thread'**
  String get thread;

  /// No description provided for @noRepliesFound.
  ///
  /// In en, this message translates to:
  /// **'No replies found'**
  String get noRepliesFound;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @failedToLoadThread.
  ///
  /// In en, this message translates to:
  /// **'Failed to load thread'**
  String get failedToLoadThread;

  /// No description provided for @closeDialog.
  ///
  /// In en, this message translates to:
  /// **'Close dialog'**
  String get closeDialog;

  /// No description provided for @pleaseSetUpProfileFirst.
  ///
  /// In en, this message translates to:
  /// **'Please set up your profile first'**
  String get pleaseSetUpProfileFirst;

  /// No description provided for @noRelayListFoundInProfile.
  ///
  /// In en, this message translates to:
  /// **'No relay list found in your profile'**
  String get noRelayListFoundInProfile;

  /// No description provided for @relaysSavedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Relays saved successfully'**
  String get relaysSavedSuccessfully;

  /// No description provided for @pleaseEnterRelayUrl.
  ///
  /// In en, this message translates to:
  /// **'Please enter a relay URL'**
  String get pleaseEnterRelayUrl;

  /// No description provided for @relayAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Relay already exists in this category'**
  String get relayAlreadyExists;

  /// No description provided for @relayAddedToMainList.
  ///
  /// In en, this message translates to:
  /// **'Relay added to Main list'**
  String get relayAddedToMainList;

  /// No description provided for @noEventsFoundToBroadcast.
  ///
  /// In en, this message translates to:
  /// **'No events found to broadcast'**
  String get noEventsFoundToBroadcast;

  /// No description provided for @errorBroadcastingEvents.
  ///
  /// In en, this message translates to:
  /// **'Error broadcasting events'**
  String get errorBroadcastingEvents;

  /// No description provided for @relayRemovedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Relay removed successfully'**
  String get relayRemovedSuccessfully;

  /// No description provided for @relaysResetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Relays reset to defaults'**
  String get relaysResetToDefaults;

  /// No description provided for @relayAddedFromFollowingList.
  ///
  /// In en, this message translates to:
  /// **'Relay added from following list'**
  String get relayAddedFromFollowingList;

  /// No description provided for @relayAlreadyExistsInList.
  ///
  /// In en, this message translates to:
  /// **'Relay already exists in your list'**
  String get relayAlreadyExistsInList;

  /// No description provided for @untitledArticle.
  ///
  /// In en, this message translates to:
  /// **'Untitled Article'**
  String get untitledArticle;

  /// No description provided for @article.
  ///
  /// In en, this message translates to:
  /// **'Article'**
  String get article;

  /// No description provided for @eventNotFound.
  ///
  /// In en, this message translates to:
  /// **'Event not found'**
  String get eventNotFound;

  /// No description provided for @articleNotFound.
  ///
  /// In en, this message translates to:
  /// **'Article not found'**
  String get articleNotFound;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @couldNotLoadHashtagFeed.
  ///
  /// In en, this message translates to:
  /// **'Could not load hashtag feed'**
  String get couldNotLoadHashtagFeed;

  /// No description provided for @errorOpeningHashtag.
  ///
  /// In en, this message translates to:
  /// **'Error opening hashtag'**
  String get errorOpeningHashtag;

  /// No description provided for @videoSavedToGallery.
  ///
  /// In en, this message translates to:
  /// **'Video saved to gallery'**
  String get videoSavedToGallery;

  /// No description provided for @failedToSaveVideoToGallery.
  ///
  /// In en, this message translates to:
  /// **'Failed to save video to gallery'**
  String get failedToSaveVideoToGallery;

  /// No description provided for @undoRepost.
  ///
  /// In en, this message translates to:
  /// **'Undo repost'**
  String get undoRepost;

  /// No description provided for @repostAgain.
  ///
  /// In en, this message translates to:
  /// **'Repost again'**
  String get repostAgain;

  /// No description provided for @quote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get quote;

  /// No description provided for @eventAndAuthorProfileSignaturesVerified.
  ///
  /// In en, this message translates to:
  /// **'Event and author profile signatures verified'**
  String get eventAndAuthorProfileSignaturesVerified;

  /// No description provided for @eventSignatureVerified.
  ///
  /// In en, this message translates to:
  /// **'Event signature verified, profile not available for verification'**
  String get eventSignatureVerified;

  /// No description provided for @eventSignatureVerificationFailed.
  ///
  /// In en, this message translates to:
  /// **'Event signature verification failed'**
  String get eventSignatureVerificationFailed;

  /// No description provided for @verificationFailed.
  ///
  /// In en, this message translates to:
  /// **'Verification failed'**
  String get verificationFailed;

  /// No description provided for @verifySignature.
  ///
  /// In en, this message translates to:
  /// **'Verify signature'**
  String get verifySignature;

  /// No description provided for @interactions.
  ///
  /// In en, this message translates to:
  /// **'Interactions'**
  String get interactions;

  /// No description provided for @errorLoadingNotes.
  ///
  /// In en, this message translates to:
  /// **'Error loading notes'**
  String get errorLoadingNotes;

  /// No description provided for @repostedBy.
  ///
  /// In en, this message translates to:
  /// **'Reposted by '**
  String get repostedBy;

  /// No description provided for @anonymous.
  ///
  /// In en, this message translates to:
  /// **'Anonymous'**
  String get anonymous;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @pleaseConnectWalletFirst.
  ///
  /// In en, this message translates to:
  /// **'Please connect your wallet first'**
  String get pleaseConnectWalletFirst;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @errorLoadingUserProfile.
  ///
  /// In en, this message translates to:
  /// **'Error loading user profile'**
  String get errorLoadingUserProfile;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @enterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get enterValidAmount;

  /// No description provided for @relaysFromYourFollows.
  ///
  /// In en, this message translates to:
  /// **'Relays from your follows'**
  String get relaysFromYourFollows;

  /// No description provided for @noRelaysFoundFromFollowingUsers.
  ///
  /// In en, this message translates to:
  /// **'No relays found from following users'**
  String get noRelaysFoundFromFollowingUsers;

  /// No description provided for @editProfileButton.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfileButton;

  /// No description provided for @mutedButton.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get mutedButton;

  /// No description provided for @followButton.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get followButton;

  /// No description provided for @followingYou.
  ///
  /// In en, this message translates to:
  /// **'Following you'**
  String get followingYou;

  /// No description provided for @imageSavedToGallery.
  ///
  /// In en, this message translates to:
  /// **'Image saved to gallery'**
  String get imageSavedToGallery;

  /// No description provided for @failedToSaveImageToGallery.
  ///
  /// In en, this message translates to:
  /// **'Failed to save image to gallery'**
  String get failedToSaveImageToGallery;

  /// No description provided for @unfollow.
  ///
  /// In en, this message translates to:
  /// **'Unfollow'**
  String get unfollow;

  /// No description provided for @pleaseEnterInvoice.
  ///
  /// In en, this message translates to:
  /// **'Please enter an invoice'**
  String get pleaseEnterInvoice;

  /// No description provided for @payInvoice.
  ///
  /// In en, this message translates to:
  /// **'Pay Invoice'**
  String get payInvoice;

  /// No description provided for @resetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to Defaults'**
  String get resetToDefaults;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get goBack;

  /// No description provided for @goBackToPreviousScreen.
  ///
  /// In en, this message translates to:
  /// **'Go back to previous screen'**
  String get goBackToPreviousScreen;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @untitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get untitled;

  /// No description provided for @noArticlesFound.
  ///
  /// In en, this message translates to:
  /// **'No articles found'**
  String get noArticlesFound;

  /// No description provided for @noRelaysFound.
  ///
  /// In en, this message translates to:
  /// **'No relays found'**
  String get noRelaysFound;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @displayTitle.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get displayTitle;

  /// No description provided for @displaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Customize your viewing experience.'**
  String get displaySubtitle;

  /// No description provided for @expandedNotes.
  ///
  /// In en, this message translates to:
  /// **'Expanded Notes'**
  String get expandedNotes;

  /// No description provided for @normalNotes.
  ///
  /// In en, this message translates to:
  /// **'Normal Notes'**
  String get normalNotes;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightMode;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @dm.
  ///
  /// In en, this message translates to:
  /// **'DM'**
  String get dm;

  /// No description provided for @wallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get wallet;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @navigationBarOrder.
  ///
  /// In en, this message translates to:
  /// **'Navigation Bar Order'**
  String get navigationBarOrder;

  /// No description provided for @pressAndHoldToDrag.
  ///
  /// In en, this message translates to:
  /// **'Press and hold to drag and reorder items'**
  String get pressAndHoldToDrag;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get notFound;

  /// No description provided for @errorLoadingKeys.
  ///
  /// In en, this message translates to:
  /// **'Error loading keys'**
  String get errorLoadingKeys;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get notAvailable;

  /// No description provided for @errorEncodingNsec.
  ///
  /// In en, this message translates to:
  /// **'Error encoding nsec'**
  String get errorEncodingNsec;

  /// No description provided for @publicKeyNpub.
  ///
  /// In en, this message translates to:
  /// **'Public Key (npub)'**
  String get publicKeyNpub;

  /// No description provided for @privateKeyNsec.
  ///
  /// In en, this message translates to:
  /// **'Private Key (nsec)'**
  String get privateKeyNsec;

  /// No description provided for @seedPhrase.
  ///
  /// In en, this message translates to:
  /// **'Seed Phrase'**
  String get seedPhrase;

  /// No description provided for @shareThisToReceiveMessages.
  ///
  /// In en, this message translates to:
  /// **'Share this with others to receive messages and zaps.'**
  String get shareThisToReceiveMessages;

  /// No description provided for @keepThisSecret.
  ///
  /// In en, this message translates to:
  /// **'Keep this secret! Never share it with anyone.'**
  String get keepThisSecret;

  /// No description provided for @useThisToRecoverAccount.
  ///
  /// In en, this message translates to:
  /// **'Use this to recover your account. Store it safely.'**
  String get useThisToRecoverAccount;

  /// No description provided for @advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advanced;

  /// No description provided for @keysTitle.
  ///
  /// In en, this message translates to:
  /// **'Keys'**
  String get keysTitle;

  /// No description provided for @keysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your Nostr identity keys.'**
  String get keysSubtitle;

  /// No description provided for @copiedToClipboardWithType.
  ///
  /// In en, this message translates to:
  /// **'{type} copied to clipboard!'**
  String copiedToClipboardWithType(String type);

  /// No description provided for @paymentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get paymentsTitle;

  /// No description provided for @paymentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your payment preferences.'**
  String get paymentsSubtitle;

  /// No description provided for @oneTapZap.
  ///
  /// In en, this message translates to:
  /// **'One Tap Zap'**
  String get oneTapZap;

  /// No description provided for @defaultZapAmount.
  ///
  /// In en, this message translates to:
  /// **'Default Zap Amount'**
  String get defaultZapAmount;

  /// No description provided for @amountSats.
  ///
  /// In en, this message translates to:
  /// **'Amount (sats)'**
  String get amountSats;

  /// No description provided for @amountSavedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Amount saved successfully'**
  String get amountSavedSuccessfully;

  /// No description provided for @pleaseEnterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid amount'**
  String get pleaseEnterValidAmount;

  /// No description provided for @mutedTitle.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get mutedTitle;

  /// No description provided for @mutedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Events from muted users and containing muted words are hidden from your feeds. Your mute list is encrypted and only visible to you.'**
  String get mutedSubtitle;

  /// No description provided for @mutedWordsTitle.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get mutedWordsTitle;

  /// No description provided for @mutedUsersTitle.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get mutedUsersTitle;

  /// No description provided for @addWordToMuteHint.
  ///
  /// In en, this message translates to:
  /// **'Add a word to mute...'**
  String get addWordToMuteHint;

  /// No description provided for @errorLoadingMutedUsers.
  ///
  /// In en, this message translates to:
  /// **'Error loading muted users'**
  String get errorLoadingMutedUsers;

  /// No description provided for @noMutedUsers.
  ///
  /// In en, this message translates to:
  /// **'No muted users'**
  String get noMutedUsers;

  /// No description provided for @youHaventMutedAnyUsersYet.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t muted any users yet.'**
  String get youHaventMutedAnyUsersYet;

  /// No description provided for @mutedUsersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} muted {count, plural, =1{user} other{users}}'**
  String mutedUsersCount(int count);

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @addRelay.
  ///
  /// In en, this message translates to:
  /// **'Add Relay'**
  String get addRelay;

  /// No description provided for @areYouSureLogout.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get areYouSureLogout;

  /// No description provided for @seedPhraseWarning.
  ///
  /// In en, this message translates to:
  /// **'IF YOU HAVEN\'T SAVED YOUR SEED PHRASE, YOU WILL LOSE YOUR ACCOUNT FOREVER.'**
  String get seedPhraseWarning;

  /// No description provided for @muteUser.
  ///
  /// In en, this message translates to:
  /// **'Mute {user}?'**
  String muteUser(String user);

  /// No description provided for @muteUserDescription.
  ///
  /// In en, this message translates to:
  /// **'You will not see notes from this user in your feed.'**
  String get muteUserDescription;

  /// No description provided for @unfollowUser.
  ///
  /// In en, this message translates to:
  /// **'Unfollow {user}?'**
  String unfollowUser(String user);

  /// No description provided for @deleteThisPost.
  ///
  /// In en, this message translates to:
  /// **'Delete this post?'**
  String get deleteThisPost;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @resetRelaysConfirm.
  ///
  /// In en, this message translates to:
  /// **'This will reset all relays to their default values. Are you sure?'**
  String get resetRelaysConfirm;

  /// No description provided for @warning.
  ///
  /// In en, this message translates to:
  /// **'Warning!'**
  String get warning;

  /// No description provided for @copyKeyWarning.
  ///
  /// In en, this message translates to:
  /// **'You can use this to import your account into qiqstr or other apps that use the Nostr protocol. Never share it with anyone.'**
  String get copyKeyWarning;

  /// No description provided for @relayUrlHint.
  ///
  /// In en, this message translates to:
  /// **'wss://relay.example.com'**
  String get relayUrlHint;

  /// No description provided for @enterSeedPhraseOrNsec.
  ///
  /// In en, this message translates to:
  /// **'Enter your seed phrase or nsec...'**
  String get enterSeedPhraseOrNsec;

  /// No description provided for @loggingIn.
  ///
  /// In en, this message translates to:
  /// **'Logging in...'**
  String get loggingIn;

  /// No description provided for @errorInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Error: Invalid input. Please check your NSEC or mnemonic phrase.'**
  String get errorInvalidInput;

  /// No description provided for @errorCouldNotCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Error: Could not create a new account.'**
  String get errorCouldNotCreateAccount;

  /// No description provided for @errorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String errorPrefix(String message);

  /// No description provided for @followers.
  ///
  /// In en, this message translates to:
  /// **'followers'**
  String get followers;

  /// No description provided for @followingCount.
  ///
  /// In en, this message translates to:
  /// **'following'**
  String get followingCount;

  /// No description provided for @saveYourSeedPhrase.
  ///
  /// In en, this message translates to:
  /// **'Save Your Seed Phrase'**
  String get saveYourSeedPhrase;

  /// No description provided for @thisIsYourOnlyChance.
  ///
  /// In en, this message translates to:
  /// **'This is your only chance to save your seed phrase. Write it down and store it safely.'**
  String get thisIsYourOnlyChance;

  /// No description provided for @iHaveSavedMySeedPhrase.
  ///
  /// In en, this message translates to:
  /// **'I have saved my seed phrase'**
  String get iHaveSavedMySeedPhrase;

  /// No description provided for @tapToCopy.
  ///
  /// In en, this message translates to:
  /// **'Tap to copy'**
  String get tapToCopy;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @bio.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get bio;

  /// No description provided for @website.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get website;

  /// No description provided for @nip05.
  ///
  /// In en, this message translates to:
  /// **'NIP-05'**
  String get nip05;

  /// No description provided for @zapAddress.
  ///
  /// In en, this message translates to:
  /// **'Zap Address'**
  String get zapAddress;

  /// No description provided for @searchUsers.
  ///
  /// In en, this message translates to:
  /// **'Search users...'**
  String get searchUsers;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching...'**
  String get searching;

  /// No description provided for @newMessage.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get newMessage;

  /// No description provided for @typeAMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get typeAMessage;

  /// No description provided for @sendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get sendMessage;

  /// No description provided for @messagePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Message...'**
  String get messagePlaceholder;

  /// No description provided for @directMessages.
  ///
  /// In en, this message translates to:
  /// **'Direct Messages'**
  String get directMessages;

  /// No description provided for @noConversationsYet.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get noConversationsYet;

  /// No description provided for @startNewConversation.
  ///
  /// In en, this message translates to:
  /// **'Start a new conversation'**
  String get startNewConversation;

  /// No description provided for @media.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get media;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @videos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videos;

  /// No description provided for @likes.
  ///
  /// In en, this message translates to:
  /// **'Likes'**
  String get likes;

  /// No description provided for @replies.
  ///
  /// In en, this message translates to:
  /// **'Replies'**
  String get replies;

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @replyingTo.
  ///
  /// In en, this message translates to:
  /// **'Replying to'**
  String get replyingTo;

  /// No description provided for @zap.
  ///
  /// In en, this message translates to:
  /// **'Zap'**
  String get zap;

  /// No description provided for @zapUser.
  ///
  /// In en, this message translates to:
  /// **'Zap {user}'**
  String zapUser(String user);

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @zapNote.
  ///
  /// In en, this message translates to:
  /// **'Zap Note'**
  String get zapNote;

  /// No description provided for @invoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get invoice;

  /// No description provided for @pasteInvoice.
  ///
  /// In en, this message translates to:
  /// **'Paste invoice'**
  String get pasteInvoice;

  /// No description provided for @paying.
  ///
  /// In en, this message translates to:
  /// **'Paying...'**
  String get paying;

  /// No description provided for @paymentSuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment successful!'**
  String get paymentSuccess;

  /// No description provided for @paymentFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment failed'**
  String get paymentFailed;

  /// No description provided for @receive.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receive;

  /// No description provided for @yourLightningAddress.
  ///
  /// In en, this message translates to:
  /// **'Your Lightning Address'**
  String get yourLightningAddress;

  /// No description provided for @scanQRCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQRCode;

  /// No description provided for @relayStatus.
  ///
  /// In en, this message translates to:
  /// **'Relay Status'**
  String get relayStatus;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// No description provided for @addRelayUrl.
  ///
  /// In en, this message translates to:
  /// **'Add relay URL'**
  String get addRelayUrl;

  /// No description provided for @removeRelay.
  ///
  /// In en, this message translates to:
  /// **'Remove relay'**
  String get removeRelay;

  /// No description provided for @eventType.
  ///
  /// In en, this message translates to:
  /// **'Event Type'**
  String get eventType;

  /// No description provided for @createdAt.
  ///
  /// In en, this message translates to:
  /// **'Created at'**
  String get createdAt;

  /// No description provided for @relayCount.
  ///
  /// In en, this message translates to:
  /// **'Relay count'**
  String get relayCount;

  /// No description provided for @deleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete selected'**
  String get deleteSelected;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get deselectAll;

  /// No description provided for @statistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statistics;

  /// No description provided for @reposts.
  ///
  /// In en, this message translates to:
  /// **'Reposts'**
  String get reposts;

  /// No description provided for @reactions.
  ///
  /// In en, this message translates to:
  /// **'Reactions'**
  String get reactions;

  /// No description provided for @zaps.
  ///
  /// In en, this message translates to:
  /// **'Zaps'**
  String get zaps;

  /// No description provided for @views.
  ///
  /// In en, this message translates to:
  /// **'Views'**
  String get views;

  /// No description provided for @filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// No description provided for @filterBy.
  ///
  /// In en, this message translates to:
  /// **'Filter by'**
  String get filterBy;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// No description provided for @newest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get newest;

  /// No description provided for @oldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get oldest;

  /// No description provided for @mostPopular.
  ///
  /// In en, this message translates to:
  /// **'Most Popular'**
  String get mostPopular;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied!'**
  String get copied;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success!'**
  String get success;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @deleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete message?'**
  String get deleteMessage;

  /// No description provided for @deleteConversation.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation?'**
  String get deleteConversation;

  /// No description provided for @areYouSureDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this?'**
  String get areYouSureDelete;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// No description provided for @report.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get report;

  /// No description provided for @reportUser.
  ///
  /// In en, this message translates to:
  /// **'Report {user}'**
  String reportUser(String user);

  /// No description provided for @reportUserDescription.
  ///
  /// In en, this message translates to:
  /// **'Select a reason for reporting this user. Your report will be published to relays.'**
  String get reportUserDescription;

  /// No description provided for @reportReasonSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam'**
  String get reportReasonSpam;

  /// No description provided for @reportReasonNudity.
  ///
  /// In en, this message translates to:
  /// **'Nudity'**
  String get reportReasonNudity;

  /// No description provided for @reportReasonProfanity.
  ///
  /// In en, this message translates to:
  /// **'Profanity'**
  String get reportReasonProfanity;

  /// No description provided for @reportReasonIllegal.
  ///
  /// In en, this message translates to:
  /// **'Illegal'**
  String get reportReasonIllegal;

  /// No description provided for @reportReasonImpersonation.
  ///
  /// In en, this message translates to:
  /// **'Impersonation'**
  String get reportReasonImpersonation;

  /// No description provided for @reportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get reportReasonOther;

  /// No description provided for @reportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Report submitted'**
  String get reportSubmitted;

  /// No description provided for @reportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit report'**
  String get reportFailed;

  /// No description provided for @selectReportReason.
  ///
  /// In en, this message translates to:
  /// **'Select a reason'**
  String get selectReportReason;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String hoursAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String daysAgo(int days);

  /// No description provided for @backupYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Backup Your Account'**
  String get backupYourAccount;

  /// No description provided for @secureYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Secure your account with your seed phrase.'**
  String get secureYourAccount;

  /// No description provided for @important.
  ///
  /// In en, this message translates to:
  /// **'Important'**
  String get important;

  /// No description provided for @writeSeedPhraseInOrder.
  ///
  /// In en, this message translates to:
  /// **'Write down your seed phrase in the correct order'**
  String get writeSeedPhraseInOrder;

  /// No description provided for @storeItSafely.
  ///
  /// In en, this message translates to:
  /// **'Store it in a safe place'**
  String get storeItSafely;

  /// No description provided for @neverShareIt.
  ///
  /// In en, this message translates to:
  /// **'Never share it with anyone'**
  String get neverShareIt;

  /// No description provided for @ifYouLoseIt.
  ///
  /// In en, this message translates to:
  /// **'If you lose it, you will lose access to your account forever'**
  String get ifYouLoseIt;

  /// No description provided for @accessFromSettings.
  ///
  /// In en, this message translates to:
  /// **'You can access this later from Settings > Keys'**
  String get accessFromSettings;

  /// No description provided for @iHaveWrittenDownSeedPhrase.
  ///
  /// In en, this message translates to:
  /// **'I have written down my seed phrase'**
  String get iHaveWrittenDownSeedPhrase;

  /// No description provided for @noNotesFromThisUser.
  ///
  /// In en, this message translates to:
  /// **'No notes from this user yet'**
  String get noNotesFromThisUser;

  /// No description provided for @fileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'File is too large (max 50MB)'**
  String get fileTooLarge;

  /// No description provided for @encryptionFailed.
  ///
  /// In en, this message translates to:
  /// **'Encryption failed'**
  String get encryptionFailed;

  /// No description provided for @errorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String errorWithMessage(String message);

  /// No description provided for @read.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get read;

  /// No description provided for @write.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get write;

  /// No description provided for @exploreRelays.
  ///
  /// In en, this message translates to:
  /// **'Explore Relays'**
  String get exploreRelays;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @mention.
  ///
  /// In en, this message translates to:
  /// **'Mention'**
  String get mention;

  /// No description provided for @searchByNameOrNpub.
  ///
  /// In en, this message translates to:
  /// **'Search by name or npub...'**
  String get searchByNameOrNpub;

  /// No description provided for @searchDotDotDot.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get searchDotDotDot;

  /// No description provided for @searchingForUsers.
  ///
  /// In en, this message translates to:
  /// **'Searching for users...'**
  String get searchingForUsers;

  /// No description provided for @searchingDotDotDot.
  ///
  /// In en, this message translates to:
  /// **'Searching...'**
  String get searchingDotDotDot;

  /// No description provided for @uploadingDotDotDot.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get uploadingDotDotDot;

  /// No description provided for @postExclamation.
  ///
  /// In en, this message translates to:
  /// **'Post!'**
  String get postExclamation;

  /// No description provided for @whatsOnYourMind.
  ///
  /// In en, this message translates to:
  /// **'What\'s on your mind?'**
  String get whatsOnYourMind;

  /// No description provided for @postingYourNotePleaseWait.
  ///
  /// In en, this message translates to:
  /// **'Posting your note, please wait'**
  String get postingYourNotePleaseWait;

  /// No description provided for @failedToLoadNotifications.
  ///
  /// In en, this message translates to:
  /// **'Failed to load notifications'**
  String get failedToLoadNotifications;

  /// No description provided for @noNotificationsYet.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get noNotificationsYet;

  /// No description provided for @whenSomeoneInteractsWithYourPosts.
  ///
  /// In en, this message translates to:
  /// **'When someone interacts with your posts,\nyou\'ll see it here'**
  String get whenSomeoneInteractsWithYourPosts;

  /// No description provided for @reactedToYourPost.
  ///
  /// In en, this message translates to:
  /// **'reacted to your post'**
  String get reactedToYourPost;

  /// No description provided for @repostedYourPost.
  ///
  /// In en, this message translates to:
  /// **'reposted your post'**
  String get repostedYourPost;

  /// No description provided for @repliedToYourPost.
  ///
  /// In en, this message translates to:
  /// **'replied to your post'**
  String get repliedToYourPost;

  /// No description provided for @mentionedYou.
  ///
  /// In en, this message translates to:
  /// **'mentioned you'**
  String get mentionedYou;

  /// No description provided for @zappedYou.
  ///
  /// In en, this message translates to:
  /// **'zapped you'**
  String get zappedYou;

  /// No description provided for @interactedWithYou.
  ///
  /// In en, this message translates to:
  /// **'interacted with you'**
  String get interactedWithYou;

  /// No description provided for @now.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get now;

  /// No description provided for @errorLoadingRelays.
  ///
  /// In en, this message translates to:
  /// **'Error loading relays'**
  String get errorLoadingRelays;

  /// No description provided for @privateKeyNotFound.
  ///
  /// In en, this message translates to:
  /// **'Private key not found. Please set up your profile first'**
  String get privateKeyNotFound;

  /// No description provided for @pleaseSetUpYourProfileFirst.
  ///
  /// In en, this message translates to:
  /// **'Please set up your profile first'**
  String get pleaseSetUpYourProfileFirst;

  /// No description provided for @relayListPublishedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Relay list published successfully'**
  String get relayListPublishedSuccessfully;

  /// No description provided for @errorPublishingRelayList.
  ///
  /// In en, this message translates to:
  /// **'Error publishing relay list'**
  String get errorPublishingRelayList;

  /// No description provided for @relayListFetchedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Relay list fetched successfully'**
  String get relayListFetchedSuccessfully;

  /// No description provided for @noRelayListFoundInYourProfile.
  ///
  /// In en, this message translates to:
  /// **'No relay list found in your profile'**
  String get noRelayListFoundInYourProfile;

  /// No description provided for @errorFetchingRelayList.
  ///
  /// In en, this message translates to:
  /// **'Error fetching relay list'**
  String get errorFetchingRelayList;

  /// No description provided for @gossipModelEnabledRestartApp.
  ///
  /// In en, this message translates to:
  /// **'Gossip model enabled. Restart the app to apply.'**
  String get gossipModelEnabledRestartApp;

  /// No description provided for @gossipModelDisabledRestartApp.
  ///
  /// In en, this message translates to:
  /// **'Gossip model disabled. Restart the app to apply.'**
  String get gossipModelDisabledRestartApp;

  /// No description provided for @errorTogglingGossipModel.
  ///
  /// In en, this message translates to:
  /// **'Error toggling Gossip model'**
  String get errorTogglingGossipModel;

  /// No description provided for @errorSavingRelays.
  ///
  /// In en, this message translates to:
  /// **'Error saving relays'**
  String get errorSavingRelays;

  /// No description provided for @invalidRelayUrl.
  ///
  /// In en, this message translates to:
  /// **'Invalid relay URL. Must start with ws:// or wss://'**
  String get invalidRelayUrl;

  /// No description provided for @relayAlreadyExistsInCategory.
  ///
  /// In en, this message translates to:
  /// **'Relay already exists in this category'**
  String get relayAlreadyExistsInCategory;

  /// No description provided for @errorAddingRelay.
  ///
  /// In en, this message translates to:
  /// **'Error adding relay'**
  String get errorAddingRelay;

  /// No description provided for @fetchingYourEvents.
  ///
  /// In en, this message translates to:
  /// **'Fetching your events...'**
  String get fetchingYourEvents;

  /// No description provided for @broadcastingEvents.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting {count} events to {relayCount} relays...'**
  String broadcastingEvents(int count, int relayCount);

  /// No description provided for @eventsSuccessfullyBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Successfully broadcast {count} events to {relayCount} relays'**
  String eventsSuccessfullyBroadcast(int count, int relayCount);

  /// No description provided for @relayAlreadyExistsInYourList.
  ///
  /// In en, this message translates to:
  /// **'Relay already exists in your list'**
  String get relayAlreadyExistsInYourList;

  /// No description provided for @fetchingRelayInformation.
  ///
  /// In en, this message translates to:
  /// **'Fetching relay information...'**
  String get fetchingRelayInformation;

  /// No description provided for @paymentRequired.
  ///
  /// In en, this message translates to:
  /// **'Payment required'**
  String get paymentRequired;

  /// No description provided for @authenticationRequired.
  ///
  /// In en, this message translates to:
  /// **'Authentication required'**
  String get authenticationRequired;

  /// No description provided for @supportedNIPs.
  ///
  /// In en, this message translates to:
  /// **'Supported NIPs'**
  String get supportedNIPs;

  /// No description provided for @software.
  ///
  /// In en, this message translates to:
  /// **'Software'**
  String get software;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contact;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @limitation.
  ///
  /// In en, this message translates to:
  /// **'Limitation'**
  String get limitation;

  /// No description provided for @maxMessageLength.
  ///
  /// In en, this message translates to:
  /// **'Max message length'**
  String get maxMessageLength;

  /// No description provided for @maxSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Max subscriptions'**
  String get maxSubscriptions;

  /// No description provided for @maxFilters.
  ///
  /// In en, this message translates to:
  /// **'Max filters'**
  String get maxFilters;

  /// No description provided for @maxLimit.
  ///
  /// In en, this message translates to:
  /// **'Max limit'**
  String get maxLimit;

  /// No description provided for @maxSubidLength.
  ///
  /// In en, this message translates to:
  /// **'Max subid length'**
  String get maxSubidLength;

  /// No description provided for @minPowDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Min PoW difficulty'**
  String get minPowDifficulty;

  /// No description provided for @viewOnWebsite.
  ///
  /// In en, this message translates to:
  /// **'View on website'**
  String get viewOnWebsite;

  /// No description provided for @eventCounts.
  ///
  /// In en, this message translates to:
  /// **'Event Counts'**
  String get eventCounts;

  /// No description provided for @eventCount.
  ///
  /// In en, this message translates to:
  /// **'{count} events'**
  String eventCount(int count);

  /// No description provided for @broadcasted.
  ///
  /// In en, this message translates to:
  /// **'broadcasted'**
  String get broadcasted;

  /// No description provided for @gossipMode.
  ///
  /// In en, this message translates to:
  /// **'Gossip Mode'**
  String get gossipMode;

  /// No description provided for @gossipModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically discover and connect to relays used by people you follow. When off, only your own relays above are used to read and write.'**
  String get gossipModeDescription;

  /// No description provided for @fetching.
  ///
  /// In en, this message translates to:
  /// **'Fetching...'**
  String get fetching;

  /// No description provided for @fetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get fetch;

  /// No description provided for @publishing.
  ///
  /// In en, this message translates to:
  /// **'Publishing...'**
  String get publishing;

  /// No description provided for @publish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publish;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @connectionStatistics.
  ///
  /// In en, this message translates to:
  /// **'Connection Statistics'**
  String get connectionStatistics;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @attempts.
  ///
  /// In en, this message translates to:
  /// **'Attempts'**
  String get attempts;

  /// No description provided for @successful.
  ///
  /// In en, this message translates to:
  /// **'Successful'**
  String get successful;

  /// No description provided for @bytesSent.
  ///
  /// In en, this message translates to:
  /// **'Bytes Sent'**
  String get bytesSent;

  /// No description provided for @bytesReceived.
  ///
  /// In en, this message translates to:
  /// **'Bytes Received'**
  String get bytesReceived;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get unknown;

  /// No description provided for @paid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paid;

  /// No description provided for @auth.
  ///
  /// In en, this message translates to:
  /// **'Auth'**
  String get auth;

  /// No description provided for @manageYourRelayConnections.
  ///
  /// In en, this message translates to:
  /// **'Manage your relay connections and publish your relay list.'**
  String get manageYourRelayConnections;

  /// No description provided for @noInteractionsYet.
  ///
  /// In en, this message translates to:
  /// **'No interactions yet.'**
  String get noInteractionsYet;

  /// No description provided for @messages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messages;

  /// No description provided for @yourDataOnRelaysDescription.
  ///
  /// In en, this message translates to:
  /// **'Everything you share on Nostr is an event. View your event count by type and resend them to relays.'**
  String get yourDataOnRelaysDescription;

  /// No description provided for @startConversationBy.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation by messaging someone'**
  String get startConversationBy;

  /// No description provided for @errorLoadingConversations.
  ///
  /// In en, this message translates to:
  /// **'Error loading conversations'**
  String get errorLoadingConversations;

  /// No description provided for @errorLoadingMessages.
  ///
  /// In en, this message translates to:
  /// **'Error loading messages: {message}'**
  String errorLoadingMessages(String message);

  /// No description provided for @notEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Not encrypted'**
  String get notEncrypted;

  /// No description provided for @videoTapToPlay.
  ///
  /// In en, this message translates to:
  /// **'Video (tap to play)'**
  String get videoTapToPlay;

  /// No description provided for @fileType.
  ///
  /// In en, this message translates to:
  /// **'File: {type}'**
  String fileType(String type);

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @noUsersFound.
  ///
  /// In en, this message translates to:
  /// **'No users found'**
  String get noUsersFound;

  /// No description provided for @trySearchingDifferentTerm.
  ///
  /// In en, this message translates to:
  /// **'Try searching with a different term.'**
  String get trySearchingDifferentTerm;

  /// No description provided for @databaseCache.
  ///
  /// In en, this message translates to:
  /// **'Database Cache'**
  String get databaseCache;

  /// No description provided for @databaseCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage local storage and cleanup old events.'**
  String get databaseCacheSubtitle;

  /// No description provided for @databaseOverview.
  ///
  /// In en, this message translates to:
  /// **'Database Overview'**
  String get databaseOverview;

  /// No description provided for @databaseSize.
  ///
  /// In en, this message translates to:
  /// **'Database Size'**
  String get databaseSize;

  /// No description provided for @totalEvents.
  ///
  /// In en, this message translates to:
  /// **'Total Events'**
  String get totalEvents;

  /// No description provided for @eventBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Event Breakdown'**
  String get eventBreakdown;

  /// No description provided for @textNotes.
  ///
  /// In en, this message translates to:
  /// **'Text Notes'**
  String get textNotes;

  /// No description provided for @profiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get profiles;

  /// No description provided for @contactLists.
  ///
  /// In en, this message translates to:
  /// **'Contact Lists'**
  String get contactLists;

  /// No description provided for @articles.
  ///
  /// In en, this message translates to:
  /// **'Articles'**
  String get articles;

  /// No description provided for @cleanupInfo.
  ///
  /// In en, this message translates to:
  /// **'Cleanup Information'**
  String get cleanupInfo;

  /// No description provided for @cleanupInfoDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically cleans up old events when database exceeds 1 GB.'**
  String get cleanupInfoDescription;

  /// No description provided for @cleanupInfoBullet1.
  ///
  /// In en, this message translates to:
  /// **'Removes events older than 30 days'**
  String get cleanupInfoBullet1;

  /// No description provided for @cleanupInfoBullet2.
  ///
  /// In en, this message translates to:
  /// **'Preserves profiles and contact lists'**
  String get cleanupInfoBullet2;

  /// No description provided for @cleanupInfoBullet3.
  ///
  /// In en, this message translates to:
  /// **'Runs automatically on app startup'**
  String get cleanupInfoBullet3;

  /// No description provided for @cleanupOldEvents.
  ///
  /// In en, this message translates to:
  /// **'Cleanup Old Events (30+ days)'**
  String get cleanupOldEvents;

  /// No description provided for @cleanupDatabase.
  ///
  /// In en, this message translates to:
  /// **'Cleanup Database'**
  String get cleanupDatabase;

  /// No description provided for @cleanupDatabaseConfirmation.
  ///
  /// In en, this message translates to:
  /// **'This will delete events older than 30 days. Profiles and lists will be preserved. Continue?'**
  String get cleanupDatabaseConfirmation;

  /// No description provided for @cleanupCompleted.
  ///
  /// In en, this message translates to:
  /// **'Cleanup completed'**
  String get cleanupCompleted;

  /// No description provided for @eventsDeleted.
  ///
  /// In en, this message translates to:
  /// **'events deleted'**
  String get eventsDeleted;

  /// No description provided for @cleanup.
  ///
  /// In en, this message translates to:
  /// **'Cleanup'**
  String get cleanup;

  /// No description provided for @addAccount.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get addAccount;

  /// No description provided for @switchAccount.
  ///
  /// In en, this message translates to:
  /// **'Switch account'**
  String get switchAccount;

  /// No description provided for @connectYourWallet.
  ///
  /// In en, this message translates to:
  /// **'Connect Your Wallet'**
  String get connectYourWallet;

  /// No description provided for @connectWalletDescription.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your Nostr identity\nto start using Coinos'**
  String get connectWalletDescription;

  /// No description provided for @connectWallet.
  ///
  /// In en, this message translates to:
  /// **'Connect Wallet'**
  String get connectWallet;

  /// No description provided for @noTransactionsYet.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get noTransactionsYet;

  /// No description provided for @recentTransactions.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentTransactions;

  /// No description provided for @received.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get received;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @pasteInvoiceHere.
  ///
  /// In en, this message translates to:
  /// **'Paste invoice here...'**
  String get pasteInvoiceHere;

  /// No description provided for @paymentSent.
  ///
  /// In en, this message translates to:
  /// **'Payment sent!'**
  String get paymentSent;

  /// No description provided for @failedToCreateInvoice.
  ///
  /// In en, this message translates to:
  /// **'Failed to create invoice: {message}'**
  String failedToCreateInvoice(String message);

  /// No description provided for @iAcceptThe.
  ///
  /// In en, this message translates to:
  /// **'I accept the '**
  String get iAcceptThe;

  /// No description provided for @termsOfUse.
  ///
  /// In en, this message translates to:
  /// **'terms of use'**
  String get termsOfUse;

  /// No description provided for @acceptanceOfTermsIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Acceptance of terms is required'**
  String get acceptanceOfTermsIsRequired;

  /// No description provided for @profileSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add some basic information to help others discover you.'**
  String get profileSetupSubtitle;

  /// No description provided for @uploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {message}'**
  String uploadFailed(String message);

  /// No description provided for @profileImageUploadedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Profile image uploaded successfully.'**
  String get profileImageUploadedSuccessfully;

  /// No description provided for @bannerUploadedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Banner uploaded successfully.'**
  String get bannerUploadedSuccessfully;

  /// No description provided for @usernameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Username must be 50 characters or less'**
  String get usernameTooLong;

  /// No description provided for @bioTooLong.
  ///
  /// In en, this message translates to:
  /// **'Bio must be 300 characters or less'**
  String get bioTooLong;

  /// No description provided for @lightningAddressOptional.
  ///
  /// In en, this message translates to:
  /// **'Lightning address (optional)'**
  String get lightningAddressOptional;

  /// No description provided for @invalidLightningAddress.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid lightning address (e.g., user@domain.com)'**
  String get invalidLightningAddress;

  /// No description provided for @websiteOptional.
  ///
  /// In en, this message translates to:
  /// **'Website (optional)'**
  String get websiteOptional;

  /// No description provided for @locationOptional.
  ///
  /// In en, this message translates to:
  /// **'Location (optional)'**
  String get locationOptional;

  /// No description provided for @locationTooLong.
  ///
  /// In en, this message translates to:
  /// **'Location must be 100 characters or less'**
  String get locationTooLong;

  /// No description provided for @newNotesAvailable.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new note} other{{count} new notes}}'**
  String newNotesAvailable(int count);

  /// No description provided for @readsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Long-form articles from people you follow.'**
  String get readsSubtitle;

  /// No description provided for @loadingArticles.
  ///
  /// In en, this message translates to:
  /// **'Loading articles...'**
  String get loadingArticles;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @noArticlesYet.
  ///
  /// In en, this message translates to:
  /// **'No articles yet'**
  String get noArticlesYet;

  /// No description provided for @longFormContentDescription.
  ///
  /// In en, this message translates to:
  /// **'Long-form content from people you follow will appear here.'**
  String get longFormContentDescription;

  /// No description provided for @bookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarks;

  /// No description provided for @bookmarksTitle.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarksTitle;

  /// No description provided for @bookmarksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your bookmarked notes are encrypted and only visible to you.'**
  String get bookmarksSubtitle;

  /// No description provided for @noBookmarks.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks'**
  String get noBookmarks;

  /// No description provided for @youHaventBookmarkedAnyNotesYet.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t bookmarked any notes yet.'**
  String get youHaventBookmarkedAnyNotesYet;

  /// No description provided for @errorLoadingBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Error loading bookmarks'**
  String get errorLoadingBookmarks;

  /// No description provided for @removeBookmark.
  ///
  /// In en, this message translates to:
  /// **'Remove bookmark'**
  String get removeBookmark;

  /// No description provided for @addBookmark.
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get addBookmark;

  /// No description provided for @bookmarkAdded.
  ///
  /// In en, this message translates to:
  /// **'Bookmark added'**
  String get bookmarkAdded;

  /// No description provided for @bookmarkRemoved.
  ///
  /// In en, this message translates to:
  /// **'Bookmark removed'**
  String get bookmarkRemoved;

  /// No description provided for @listsTitle.
  ///
  /// In en, this message translates to:
  /// **'Lists'**
  String get listsTitle;

  /// No description provided for @listsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Organize people you follow into categorized groups.'**
  String get listsSubtitle;

  /// No description provided for @noLists.
  ///
  /// In en, this message translates to:
  /// **'No lists'**
  String get noLists;

  /// No description provided for @noListsDescription.
  ///
  /// In en, this message translates to:
  /// **'Create a list to organize people you follow.'**
  String get noListsDescription;

  /// No description provided for @errorLoadingLists.
  ///
  /// In en, this message translates to:
  /// **'Error loading lists'**
  String get errorLoadingLists;

  /// No description provided for @createList.
  ///
  /// In en, this message translates to:
  /// **'Create List'**
  String get createList;

  /// No description provided for @listNameHint.
  ///
  /// In en, this message translates to:
  /// **'List name'**
  String get listNameHint;

  /// No description provided for @listDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get listDescriptionHint;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @memberCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No members} =1{1 member} other{{count} members}}'**
  String memberCount(int count);

  /// No description provided for @noMembersInList.
  ///
  /// In en, this message translates to:
  /// **'No members'**
  String get noMembersInList;

  /// No description provided for @noMembersInListDescription.
  ///
  /// In en, this message translates to:
  /// **'Add people to this list from their profile.'**
  String get noMembersInListDescription;

  /// No description provided for @removeFromList.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeFromList;

  /// No description provided for @addToList.
  ///
  /// In en, this message translates to:
  /// **'Add to list'**
  String get addToList;

  /// No description provided for @deleteList.
  ///
  /// In en, this message translates to:
  /// **'Delete list'**
  String get deleteList;

  /// No description provided for @listsFromFollows.
  ///
  /// In en, this message translates to:
  /// **'From people you follow'**
  String get listsFromFollows;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get all;

  /// No description provided for @addToFeed.
  ///
  /// In en, this message translates to:
  /// **'Add to feed'**
  String get addToFeed;

  /// No description provided for @removeFromFeed.
  ///
  /// In en, this message translates to:
  /// **'Remove from feed'**
  String get removeFromFeed;

  /// No description provided for @addAnotherFeed.
  ///
  /// In en, this message translates to:
  /// **'+ Add feed'**
  String get addAnotherFeed;

  /// No description provided for @onboardingCoinosTitle.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin Wallet'**
  String get onboardingCoinosTitle;

  /// No description provided for @onboardingCoinosSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set up a built-in Lightning wallet to send, receive, and zap sats instantly.'**
  String get onboardingCoinosSubtitle;

  /// No description provided for @onboardingCoinosConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect Wallet'**
  String get onboardingCoinosConnect;

  /// No description provided for @onboardingCoinosFeatureSend.
  ///
  /// In en, this message translates to:
  /// **'Send Bitcoin payments instantly via Lightning Network'**
  String get onboardingCoinosFeatureSend;

  /// No description provided for @onboardingCoinosFeatureReceive.
  ///
  /// In en, this message translates to:
  /// **'Receive Bitcoin with your own Lightning address'**
  String get onboardingCoinosFeatureReceive;

  /// No description provided for @onboardingCoinosFeatureZap.
  ///
  /// In en, this message translates to:
  /// **'Send Bitcoin to your favorite posts and creators'**
  String get onboardingCoinosFeatureZap;

  /// No description provided for @onboardingCoinosDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'This wallet is provided by coinos.io. We do not hold, control, or have access to your funds. All responsibility regarding the wallet service lies with coinos.io.'**
  String get onboardingCoinosDisclaimer;

  /// No description provided for @onboardingCoinosAccept.
  ///
  /// In en, this message translates to:
  /// **'I understand and agree'**
  String get onboardingCoinosAccept;

  /// No description provided for @onboardingCoinosConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected as {username}@coinos.io'**
  String onboardingCoinosConnected(String username);

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome!'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A decentralized social network built on Nostr. Fully open source.'**
  String get welcomeSubtitle;

  /// No description provided for @welcomeFeatureDecentralized.
  ///
  /// In en, this message translates to:
  /// **'No central servers, no CEOs. Nobody can ban you.'**
  String get welcomeFeatureDecentralized;

  /// No description provided for @welcomeFeatureKeys.
  ///
  /// In en, this message translates to:
  /// **'Own your identity with your own keys.'**
  String get welcomeFeatureKeys;

  /// No description provided for @welcomeFeatureBitcoin.
  ///
  /// In en, this message translates to:
  /// **'Message securely with end-to-end encryption.'**
  String get welcomeFeatureBitcoin;

  /// No description provided for @welcomeAlreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get welcomeAlreadyHaveAccount;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your seed phrase or nsec key to sign in to your existing account.'**
  String get loginSubtitle;

  /// No description provided for @loginExampleSeed.
  ///
  /// In en, this message translates to:
  /// **'e.g. istanbul relay key note zap feed post sign bolt send trust free'**
  String get loginExampleSeed;

  /// No description provided for @loginExampleNsec.
  ///
  /// In en, this message translates to:
  /// **'e.g. nsec1234567abcde1234567abcde...'**
  String get loginExampleNsec;

  /// No description provided for @signupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A new Nostr identity will be generated for you. You will receive a seed phrase to back up your account.'**
  String get signupSubtitle;

  /// No description provided for @signupFeatureKeys.
  ///
  /// In en, this message translates to:
  /// **'A unique cryptographic key pair will be created for you'**
  String get signupFeatureKeys;

  /// No description provided for @signupFeatureBackup.
  ///
  /// In en, this message translates to:
  /// **'You will get a seed phrase to securely back up your account'**
  String get signupFeatureBackup;

  /// No description provided for @signupFeatureProfile.
  ///
  /// In en, this message translates to:
  /// **'Set up your profile and start connecting with others'**
  String get signupFeatureProfile;

  /// No description provided for @signupCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating your account...'**
  String get signupCreating;

  /// No description provided for @followedByCount.
  ///
  /// In en, this message translates to:
  /// **'Followed by {count, plural, =1{1 person} other{{count} people}} you follow'**
  String followedByCount(int count);

  /// No description provided for @pinNote.
  ///
  /// In en, this message translates to:
  /// **'Pin note'**
  String get pinNote;

  /// No description provided for @unpinNote.
  ///
  /// In en, this message translates to:
  /// **'Unpin note'**
  String get unpinNote;

  /// No description provided for @notePinned.
  ///
  /// In en, this message translates to:
  /// **'Note pinned to profile'**
  String get notePinned;

  /// No description provided for @noteUnpinned.
  ///
  /// In en, this message translates to:
  /// **'Note unpinned from profile'**
  String get noteUnpinned;

  /// No description provided for @pinnedNotes.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinnedNotes;

  /// No description provided for @processingPayment.
  ///
  /// In en, this message translates to:
  /// **'Processing payment...'**
  String get processingPayment;

  /// No description provided for @zappedSatsToUser.
  ///
  /// In en, this message translates to:
  /// **'Zapped {sats} {sats, plural, =1{sat} other{sats}} to {user}!'**
  String zappedSatsToUser(int sats, String user);

  /// No description provided for @failedToZap.
  ///
  /// In en, this message translates to:
  /// **'Failed to zap'**
  String get failedToZap;

  /// No description provided for @userNoLightningAddress.
  ///
  /// In en, this message translates to:
  /// **'User does not have a lightning address configured.'**
  String get userNoLightningAddress;

  /// No description provided for @commentOptional.
  ///
  /// In en, this message translates to:
  /// **'Comment (Optional)'**
  String get commentOptional;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
