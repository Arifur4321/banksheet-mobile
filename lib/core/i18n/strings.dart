/// User-facing copy.
///
/// The Laravel app carries 13 locale catalogues with 1881 aligned keys each. To
/// avoid a second, drifting copy of that catalogue — and to keep the app
/// buildable with no codegen — the client ships English only and asks the
/// server for localised content (validation messages, plan names, error detail)
/// by sending the user's chosen locale on `PATCH /me`.
///
/// When it is time to localise the client, this class is the extraction point:
/// every literal is here, none are inline in widgets.
library;

abstract final class S {
  // ------------------------------------------------------------------ brand
  static const String appName = 'BankSheet Pro';
  static const String tagline = 'Bank statements to spreadsheets, in seconds.';

  // ------------------------------------------------------------------- auth
  static const String welcomeTitle = 'Turn any bank statement into clean data';
  static const String welcomeBody =
      'Upload a PDF, get reconciled transactions you can review and export. '
      'Plus PDF tools, barcodes and e-signature.';
  static const String signIn = 'Sign in';
  static const String signUp = 'Create account';
  static const String createFreeAccount = 'Create a free account';
  static const String alreadyHaveAccount = 'I already have an account';
  static const String email = 'Email';
  static const String password = 'Password';
  static const String confirmPassword = 'Confirm password';
  static const String currentPassword = 'Current password';
  static const String newPassword = 'New password';
  static const String fullName = 'Your name';
  static const String workspaceName = 'Workspace name';

  /// The sign-up form's label for the same field. It is optional on the phone —
  /// left blank, the server names the workspace after the person — and a field
  /// that says nothing is read as required, so this one says so.
  static const String workspaceNameOptional = 'Workspace name (optional)';
  static const String workspaceHint = 'Usually your company or practice name';
  static const String forgotPassword = 'Forgot password?';
  static const String resetPassword = 'Reset password';
  static const String resetSent =
      'If that address has an account, a reset link is on its way.';
  static const String signOut = 'Sign out';
  static const String signOutConfirm = 'Sign out of this device?';
  static const String signInSubtitle = 'Welcome back. Your workspace is ready.';
  static const String signUpSubtitle =
      'Free to start, no card needed. Ten documents a month on the house.';
  static const String forgotPasswordSubtitle =
      'Enter the address you signed up with and we will send you a link.';
  static const String sendResetLink = 'Send reset link';
  static const String backToSignIn = 'Back to sign in';
  static const String checkYourInbox = 'Check your inbox';
  static const String invalidEmail = 'Enter a valid email address';
  static const String passwordTooShort = 'Use at least 8 characters';
  static const String passwordsDoNotMatch = 'The two passwords do not match';
  static const String showPassword = 'Show password';
  static const String hidePassword = 'Hide password';
  static const String noAccountYet = 'New here?';
  static const String haveAccount = 'Already have an account?';
  static const String valueReconciled = 'Reconciled totals, not raw text';
  static const String valuePdfTools = 'Thirteen PDF tools in your pocket';

  /// Not currently rendered. The welcome screen shows two of these three
  /// bullets, and only on a tall phone — the two action tiles took the space.
  /// Kept for the store listing copy and for whichever screen wants it next.
  static const String valueEsign = 'Send documents for e-signature';
  static const String termsNotice =
      'By creating an account you agree to the Terms of Service and the '
      'Privacy Policy.';

  // -------------------------------------------------------------- dashboard
  static const String dashboard = 'Dashboard';
  static const String goodMorning = 'Good morning';
  static const String goodAfternoon = 'Good afternoon';
  static const String goodEvening = 'Good evening';
  static const String quickActions = 'Quick actions';
  static const String recentDocuments = 'Recent documents';
  static const String viewAll = 'View all';
  static const String usageThisMonth = 'Usage this month';
  static const String dashboardHeroTitle = 'Statements in, spreadsheets out';
  static const String greetingFallback = 'there';
  static const String uploadStatement = 'Upload a statement';
  static const String openAccount = 'Account and settings';
  static const String statProcessedDocuments = 'Processed documents';
  static const String statPendingReviews = 'Pending reviews';
  static const String statSavedExports = 'Saved exports';
  static const String statFailedDocuments = 'Failed documents';
  static const String usagePages = 'Pages';
  static const String usageEsign = 'E-signatures';
  static const String usageWebScans = 'Web scans';
  static const String usageBarcodes = 'Barcodes';
  static const String usageResets = 'Resets';
  static const String emailsFound = 'Emails found';

  // -------------------------------------------------------------- documents
  static const String documents = 'Documents';
  static const String documentsSubtitle = 'Statements, invoices and PDFs';
  static const String uploadDocument = 'Upload document';
  static const String chooseFile = 'Choose a file';
  static const String scanWithCamera = 'Scan with camera';
  static const String scanHint = 'Photograph each page — we build the PDF';
  static const String documentType = 'Document type';
  static const String bankStatement = 'Bank statement';
  static const String invoice = 'Invoice';
  static const String genericPdf = 'Other PDF';
  static const String extractionProfile = 'Extraction profile';
  static const String autoMatchProfile = 'Auto-match the best profile';
  static const String reprocess = 'Run extraction again';
  static const String downloadOriginal = 'Download original';
  static const String exportData = 'Export data';
  static const String statementSummary = 'Statement summary';
  static const String reconciliation = 'Reconciliation';
  static const String transactions = 'Transactions';
  static const String noDocuments = 'No documents yet';
  static const String noDocumentsBody =
      'Upload a bank statement PDF and we will extract every transaction.';
  static const String processingDocument = 'Extracting…';
  static const String processingBody =
      'This usually takes 10–90 seconds. You can leave this screen.';
  static const String untitledDocument = 'Untitled document';
  static const String rowsExtracted = 'rows';

  // -- list, upload and detail (documents agent) ---------------------------
  static const String searchDocuments = 'Search by filename';
  static const String filterWorking = 'Working';
  static const String filterDone = 'Done';
  static const String filterFailed = 'Failed';
  static const String noResults = 'Nothing matched';
  static const String noResultsBody =
      'Try a different search, or clear the filters to see everything.';
  static const String clearFilters = 'Clear filters';
  static const String couldNotLoadMore = 'Could not load the next page.';
  static const String acceptedFormats = 'PDF, XML, P7M, JPG, PNG or ZIP';
  static const String acceptedFormatsBody =
      'PDF, e-invoice XML or P7M, JPG, PNG or ZIP — up to 20 MB per file.';
  static const String fileHint = 'Pick a PDF or an e-invoice from your files';
  static const String filePickFailed =
      'That file could not be read. Try picking it again.';
  static const String scanPages = 'Scanned pages';
  static const String reorderHint = 'Drag to reorder — this is the page order';
  static const String addPage = 'Add another page';
  static const String removePage = 'Remove page';
  static const String discardPages = 'Discard these pages';
  static const String buildingPdf = 'Building your PDF…';
  static const String scanFilenamePrefix = 'scan';
  static const String changeFile = 'Change';
  static const String unprocessableUpload =
      'This file will be stored, but JPG, PNG and ZIP uploads cannot be '
      'extracted yet. Use the camera option to build a PDF instead.';
  static const String uploadNow = 'Upload';
  static const String uploadingDocument = 'Uploading…';
  static const String documentUploaded = 'Uploaded. Extraction has started.';
  static const String alreadyUploaded =
      'That file was already uploaded — opening it instead.';
  static const String profilesUnavailable =
      'Profiles could not be loaded. Auto-match will be used.';
  static const String stageUploaded = 'Received — waiting for a worker';
  static const String stageQueued = 'Queued behind other documents';
  static const String stageProcessing = 'Reading the pages';
  static const String stageFinishing = 'Finishing up';
  static const String pollingStopped =
      'We stopped checking for updates. Pull down to refresh.';
  static const String documentFailed = 'Extraction failed.';
  static const String onlyPdfsReprocess = 'Only PDFs can be extracted again.';
  static const String reprocessTitle = 'Run extraction again';
  static const String reprocessBody =
      'Choose the layout to parse with, or let us match one automatically.';
  static const String reprocessStarted = 'Extraction restarted.';
  static const String deleteDocument = 'Delete this document?';
  static const String deleteDocumentBody =
      'This removes the document, every extracted row and every export made '
      'from it. This cannot be undone.';
  static const String documentDeleted = 'Document deleted.';
  static const String reviewProgress = 'Review progress';
  static const String notAStatementBody =
      'This is not a bank statement, so there are no transaction rows to '
      'review. Export it to see what was extracted.';
  static const String noTransactions = 'No rows extracted';
  static const String noTransactionsBody =
      'The extractor did not find any transaction rows in this document. '
      'Try running it again with a different profile.';

  // -- statement summary ---------------------------------------------------
  static const String bank = 'Bank';
  static const String accountHolder = 'Account holder';
  static const String account = 'Account';
  static const String period = 'Period';
  static const String openingBalance = 'Opening balance';
  static const String closingBalance = 'Closing balance';
  static const String totalDebits = 'Money out';
  static const String totalCredits = 'Money in';
  static const String netChange = 'Net change';
  static const String extractionWarnings = 'Extraction notes';
  static const String confidence = 'Confidence';
  static const String confidenceCertain = 'Certain';
  static const String confidenceHigh = 'High';
  static const String confidenceMedium = 'Medium';
  static const String confidenceLow = 'Low';

  // -- reconciliation ------------------------------------------------------
  static const String statementBalanced = 'This statement balances';
  static const String statementBalancedBody =
      'The opening balance plus every credit minus every debit equals the '
      'closing balance';
  static const String statementUnbalanced = 'This statement does not balance';
  static const String reconciliationUnknown = 'We could not check this one';
  static const String reconciliationUnknownBody =
      'The statement did not report both an opening and a closing balance, so '
      'there is nothing to check the rows against';
  static const String expectedNetChange = 'Expected change';
  static const String computedNetChange = 'Change from the rows';
  static const String discrepancy = 'Difference';
  static const String rowsChecked = 'Checked';
  static const String rowsMatched = 'Matched';
  static const String rowsFlagged = 'Flagged';

  // -- export --------------------------------------------------------------
  static const String exportFormat = 'Export this document';
  static const String exportFormatBody =
      'Only approved rows are included. Pick a format.';
  static const String exportXlsx = 'Excel workbook';
  static const String exportXlsxBody = 'One sheet, formatted, opens anywhere';
  static const String exportCsv = 'CSV';
  static const String exportCsvBody = 'Plain text, for imports and bookkeeping';
  static const String exportJson = 'JSON';
  static const String exportJsonBody = 'The full structure, for developers';
  static const String exportReady = 'Export ready.';
  static const String recentExports = 'Already exported';

  // -- counted strings -----------------------------------------------------
  static String documentCount(int count) =>
      count == 1 ? '1 document' : '$count documents';

  static String pageCount(int count) => count == 1 ? '1 page' : '$count pages';

  static String transactionCount(int count) =>
      count == 1 ? '1 row' : '$count rows';

  static String pageNumber(int number) => 'Page $number';

  static String createPdfFrom(int pages) =>
      pages == 1 ? 'Create a 1 page PDF' : 'Create a $pages page PDF';

  static String scanPageUnreadable(int page) =>
      'Page $page could not be read. Remove it and photograph it again.';

  static String fileTooLarge(String size, String limit) =>
      'That file is $size. The limit is $limit — split it or compress it '
      'before uploading.';

  static String profileNumber(int id) => 'Profile $id';

  static String rowsFoundSoFar(int count) =>
      count == 1 ? '1 row found so far' : '$count rows found so far';

  static String approvedOf(int approved, int total) => '$approved / $total';

  static String statementUnbalancedBody(String difference) =>
      'The rows are out by $difference against the closing balance. Check the '
      'flagged rows before exporting';

  // ------------------------------------------------------------ review queue
  static const String reviewQueue = 'Review queue';
  static const String reviewSubtitle = 'Check what the extractor found';
  static const String approve = 'Approve';
  static const String reject = 'Reject';
  static const String approveAll = 'Approve all rows';
  static const String approveAllConfirm =
      'Approve every pending row on this document?';
  static const String pendingReview = 'Pending review';
  static const String approved = 'Approved';
  static const String rejected = 'Rejected';
  static const String edited = 'Edited';
  static const String nothingToReview = 'Nothing to review';
  static const String nothingToReviewBody =
      'Every extracted row has been checked. Nice work.';
  static const String needsReview = 'Needs review';

  // -- swipe decisions and the row editor (documents agent) ----------------
  static const String approveAllVisible = 'Approve all visible';
  static const String approveAllVisibleConfirm =
      'Approve every row currently loaded on this screen?';
  static const String rowApproved = 'Row approved';
  static const String rowRejected = 'Row rejected';
  static const String undo = 'Undo';
  static const String swipeHint = 'Swipe right to approve, left to reject';
  static const String openDocument = 'Open document';
  static const String fromDocument = 'From';
  static const String noRowsHere = 'Nothing here';
  static const String noRowsHereBody =
      'No rows have that status yet. Try another filter.';
  static const String editTransaction = 'Edit row';
  static const String saveChanges = 'Save changes';
  static const String transactionUpdated = 'Row updated.';
  static const String sourceLine = 'What the parser read';
  static const String date = 'Date';
  static const String valueDate = 'Value date';
  static const String description = 'Description';
  static const String reference = 'Reference';
  static const String counterparty = 'Counterparty';
  static const String category = 'Category';
  static const String debit = 'Money out';
  static const String credit = 'Money in';
  static const String balance = 'Balance';
  static const String currency = 'Currency';
  static const String mustBeNumber = 'Enter a number';
  static const String tooLong = 'That is too long';

  static String rowsWaiting(int count) =>
      count == 1 ? '1 row waiting' : '$count rows waiting';

  static String approvedRows(int count) =>
      count == 1 ? 'Approved 1 row.' : 'Approved $count rows.';

  static String lastReviewedBy(String name, String when) =>
      'Last reviewed by $name, $when';

  // ------------------------------------------------------------------ tools
  static const String pdfTools = 'PDF tools';
  static const String pdfToolsSubtitle = 'Convert, merge, split, compress, OCR';
  static const String conversions = 'Conversions';
  static const String convert = 'Convert';
  static const String openResult = 'Open result';
  static const String downloadResult = 'Download';
  static const String retry = 'Try again';

  // -- catalogue, run screen and history (tools agent) ---------------------
  static const String toolsPdfUtilities = 'PDF utilities';
  static const String toolsDocumentConversion = 'Document conversion';
  static const String toolsImageConversion = 'Image conversion';
  static const String moreTools = 'More tools';
  static const String recentConversions = 'Recent conversions';
  static const String toolWebOnly =
      'The visual PDF editor is only available on banksheet.pro.';
  static const String choose = 'Choose';
  static const String decrease = 'Less';
  static const String increase = 'More';
  static const String remove = 'Remove';
  static const String chooseFiles = 'Choose files';
  static const String addFiles = 'Add more';
  static const String uploadingFiles = 'Uploading…';
  static const String conversionQueued = 'Queued';
  static const String conversionRunning = 'Converting…';
  static const String conversionWaitBody =
      'Your file is on the server. This usually takes a few seconds — you can '
      'leave this screen and find it under Conversions.';
  static const String conversionReady = 'Ready';
  static const String conversionFailed = 'That conversion failed.';
  static const String convertAnother = 'Convert another';
  static const String outputUnavailable =
      'The output file is no longer available. Run the tool again to make a '
      'new one.';
  static const String noConversions = 'Nothing converted yet';
  static const String noConversionsBody =
      'Pick a tool above and your finished files will show up here.';
  static const String conversionRequeued = 'Queued again.';
  static const String deleteConversion = 'Delete this conversion?';
  static const String deleteConversionBody =
      'This removes the conversion, the file it produced and the private '
      'source files you uploaded. This cannot be undone.';
  static const String conversionDeleted = 'Conversion deleted.';
  static const String cannotOpenFile = 'That file could not be opened.';
  static const String noAppForFile =
      'No app on this device can open that file. Try sharing it instead.';
  static const String invalidChoice = 'Pick one of the listed values';
  static const String invalidFormat = 'That format is not accepted';
  static const String invalidJson = 'Enter a valid JSON object';

  static String toolNotFound(String key) =>
      'The tool "$key" is not available on this account.';

  static String conversionsLeft(int count) => count == 1
      ? '1 conversion left this month'
      : '$count conversions left this month';

  static String conversionCount(int count) =>
      count == 1 ? '1 conversion' : '$count conversions';

  static String savedAs(String filename) => 'Saved as $filename';

  static String tooManyFiles(int max) =>
      max == 1 ? 'Only one file at a time' : 'Up to $max files at a time';

  static String needAtLeastFiles(int min) =>
      min == 1 ? 'Choose a file first' : 'Choose at least $min files';

  static String totalTooLarge(String limit) =>
      'Those files add up to more than $limit. Remove one or compress them.';

  static String upToFiles(int max, String size) =>
      'Up to $max files, $size each';

  static String upToSize(String size) => 'Up to $size';

  static String maxCharacters(int max) => 'Use at most $max characters';

  static String valueBetween(int min, int max) =>
      'Enter a value from $min to $max';

  static String valueAtLeast(int min) => 'Enter $min or more';

  static String valueAtMost(int max) => 'Enter $max or less';

  // ---------------------------------------------------------------- barcode
  static const String barcode = 'Barcode generator';
  static const String barcodeSubtitle = 'QR, EAN, Code 128, Data Matrix';
  static const String symbology = 'Type';
  static const String barcodeValue = 'Value to encode';
  static const String generate = 'Generate';
  static const String livePreview = 'Live preview';

  // -- generator form and downloads (tools agent) --------------------------
  static const String barcodeCardBody =
      'QR codes, EAN, UPC, Code 128, Data Matrix and PDF417 as PNG or SVG.';
  static const String barcodeValueHint = 'What the barcode should encode';
  static const String barcodePreviewHint =
      'Pick a type and enter a value — the preview updates as you type.';
  static const String barcodeAppearance = 'Appearance';
  static const String barcodeScale = 'Module size';
  static const String barcodeHeight = 'Bar height';
  static const String barcodeQuietZone = 'Quiet zone';
  static const String barcodeForeground = 'Bars';
  static const String barcodeBackground = 'Background';
  static const String barcodeShowText = 'Print the value under the barcode';
  static const String barcodeTransparent = 'Transparent background';
  static const String barcodeTransparentBody =
      'Only the PNG and SVG keep transparency — a printed label will use the '
      'paper colour.';
  static const String barcodeColourFormat = 'Use a colour like #1A2B3C';
  static const String barcodeGenerated = 'Barcode generated.';
  static const String barcodeSaved = 'Saved to your workspace';
  static const String barcodePng = 'PNG';
  static const String barcodeSvg = 'SVG';
  static const String barcodeValueRequired =
      'Enter the data to encode in the barcode.';
  static const String barcodeValueTooLong = 'The barcode data is too long.';

  static String barcodesLeft(int count) => count == 1
      ? '1 barcode left this month'
      : '$count barcodes left this month';

  static String barcodeMaxCharacters(String label, int max) =>
      '$label supports up to $max characters.';

  static String barcodeUnsupportedCharacters(String label) =>
      '$label contains unsupported characters.';

  static String barcodeDigitsOnly(String label) => '$label accepts digits only.';

  static String barcodeDigitCount(String label, int data, int full) =>
      '$label requires $data digits (the check digit is added) or $full digits '
      'including the check digit.';

  static String barcodeCheckDigit(String label, int digit) =>
      'The $label check digit is incorrect. Expected $digit.';

  // ---------------------------------------------------------- web extraction
  static const String webExtraction = 'Web to Excel';
  static const String webExtractionSubtitle =
      'Find public business contacts from a list of domains';
  static const String domains = 'Domains';
  static const String domainsHint = 'One per line, e.g. example.com';
  static const String startCrawl = 'Start extraction';
  static const String results = 'Results';
  static const String cancelJob = 'Cancel';

  // -- jobs, progress, results and export (tools agent) --------------------
  static const String webExtractionCardBody =
      'Paste a list of company websites and get their published contacts as a '
      'spreadsheet.';
  static const String newExtraction = 'New extraction';
  static const String queueExtraction = 'Queue extraction';
  static const String extractionQueued = 'Web extraction job queued.';
  static const String extractionRunning = 'Extraction running';
  static const String extractionFinished = 'Extraction finished';
  static const String noExtractions = 'No extractions yet';
  static const String noExtractionsBody =
      'Paste a list of company websites and we will collect the contact '
      'details they publish.';
  static const String currentAllowance = 'Current allowance';
  static const String jobTitle = 'Name this job';
  static const String jobTitleHint = 'Optional — e.g. Milan suppliers';
  static const String domainsCountHint =
      'One website per line. Commas and semicolons work too.';
  static const String domainListTooLong =
      'That list is too long. Split it into smaller jobs.';
  static const String noWebsitesFound =
      'No websites found in that text yet.';
  static const String responsibleUseNotice =
      'Responsible use: this tool extracts publicly available business '
      'information from official websites. Do not use it for spam or unlawful '
      'outreach.';
  static const String whatWeCheck = 'What BankSheet checks';
  static const String crawlPointHomepage =
      'Official homepage and same-domain public pages';
  static const String crawlPointPages =
      'Contact, careers, about, team and management pages first';
  static const String crawlPointData =
      'Published emails, phones, addresses, VAT numbers, people and social '
      'links';
  static const String crawlPointSafety =
      'robots.txt, redirect, size, timeout and private-network safety rules';
  static const String cancelJobBody =
      'The websites still queued will be stopped. Everything already extracted '
      'stays available to export.';
  static const String jobCancelled = 'Extraction cancelled.';
  static const String jobRetried = 'Failed websites were queued again.';
  static const String retryFailed = 'Retry failed';
  static const String deleteJob = 'Delete this extraction?';
  static const String deleteJobBody =
      'This removes the job, every website in it and the spreadsheets built '
      'from it. This cannot be undone.';
  static const String jobDeleted = 'Extraction deleted.';
  static const String viewResults = 'View results';
  static const String websites = 'Websites';
  static const String noWebsitesYet = 'No websites in this job yet.';
  static const String showMoreWebsites = 'Show more websites';
  static const String careerPagesFound = 'Career pages';
  static const String websitesFailed = 'Unusable';
  static const String targetSkipped = 'Not a usable website — skipped';
  static const String targetWorking = 'Reading the site…';
  static const String resultEmails = 'Emails';
  static const String resultPecEmails = 'Certified mail (PEC)';
  static const String resultPhones = 'Phones';
  static const String resultVat = 'VAT numbers';
  static const String resultAddresses = 'Addresses';
  static const String resultPeople = 'People';
  static const String resultSocials = 'Social profiles';
  static const String nothingExtracted =
      'Nothing was published on this site that we could read.';
  static const String openSource = 'Source';
  static const String noResultsYet = 'No results yet';
  static const String noResultsYetBody =
      'Results appear here as each website is read.';
  static const String noResultsFiltered =
      'No website in this job published an email address.';
  static const String filterWithEmail = 'With an email';
  static const String webExportTitle = 'Export these results';
  static const String webExportBody =
      'The same file the website builds, with a source URL on every value.';
  static const String webExportXlsxBody =
      'One workbook, one sheet per section, ready to filter';
  static const String webExportCsvBody = 'Plain text, for imports and CRMs';
  static const String couldNotOpenLink = 'That link could not be opened.';

  static String jobCount(int count) =>
      count == 1 ? '1 extraction' : '$count extractions';

  static String websiteCount(int count) =>
      count == 1 ? '1 website' : '$count websites';

  static String emailCount(int count) =>
      count == 1 ? '1 email' : '$count emails';

  static String websitesProcessed(int done, int total) =>
      '$done of $total websites processed';

  static String websitesUnusable(int count) =>
      count == 1 ? '1 website could not be read' : '$count websites could not be read';

  static String websitesWillBeScanned(int count) => count == 1
      ? '1 website will be scanned'
      : '$count websites will be scanned';

  static String linesIgnored(int count, String sample) => count == 1
      ? '1 line is not a website and will be ignored: $sample'
      : '$count lines are not websites and will be ignored: $sample';

  static String queueExtractionCount(int count) => count == 1
      ? 'Queue extraction for 1 website'
      : 'Queue extraction for $count websites';

  static String scansRemaining(int count) =>
      count == 1 ? '1 scan remaining' : '$count scans remaining';

  static String pagesScanned(int count) =>
      count == 1 ? '1 page scanned' : '$count pages scanned';

  static String sourceAndMore(String url, int extra) =>
      extra == 1 ? '$url and 1 more page' : '$url and $extra more pages';

  // -------------------------------------------------------------- templates
  static const String templates = 'Templates';
  static const String generatedPdfs = 'Generated PDFs';
  static const String generatePdf = 'Generate PDF';
  static const String fillVariables = 'Fill in the details';

  // -- templates and generated PDFs (content agent) ------------------------
  static const String templatesSubtitle = 'Fill one in, get a PDF back';
  static const String templatesAuthoredOnWeb =
      'Templates are designed on banksheet.pro. Here you fill one in and get '
      'the PDF.';
  static const String noTemplates = 'No templates yet';
  static const String noTemplatesBody =
      'Build a template on banksheet.pro and it appears here, ready to fill in '
      'from your phone.';
  static const String generatedPdfsSubtitle = 'Everything you have generated';
  static const String noGeneratedPdfs = 'Nothing generated yet';
  static const String noGeneratedPdfsBody =
      'Fill in a template and the finished PDF is kept here for you.';
  static const String documentTitle = 'Document title';
  static const String documentTitleHint = 'What this PDF will be called';
  static const String noVariables = 'Nothing to fill in';
  static const String noVariablesBody =
      'This template has no fields, so it generates exactly as it is.';
  static const String generating = 'Generating…';
  static const String pdfReady = 'Your PDF is ready';
  static const String seeAllGeneratedPdfs = 'See all generated PDFs';
  static const String generateAnother = 'Generate another';
  static const String selectOption = 'Choose one';
  static const String pickDate = 'Pick a date';
  static const String fromTemplate = 'From a template';
  static const String contractPdf = 'Contract';
  static const String uploadedPdf = 'Uploaded PDF';
  static const String untitledTemplate = 'Untitled template';
  static const String untitledPdf = 'Untitled PDF';
  static const String invalidDate = 'Enter a valid date';

  static String templateCount(int count) =>
      count == 1 ? '1 template' : '$count templates';

  static String templateFieldCount(int count) =>
      count == 1 ? '1 field' : '$count fields';

  static String generatedPdfCount(int count) =>
      count == 1 ? '1 PDF' : '$count PDFs';

  static String signatureFieldCount(int count) =>
      count == 1 ? '1 signature field' : '$count signature fields';

  // ------------------------------------------------------------------ esign
  static const String signatures = 'E-signature';
  static const String signaturesSubtitle = 'Track what you sent for signing';
  static const String signers = 'Signers';
  static const String downloadSigned = 'Download signed PDF';

  // -- signature tracking (content agent) ----------------------------------
  static const String noSignatureRequests = 'Nothing out for signature';
  static const String noSignatureRequestsBody =
      'Requests you send from banksheet.pro appear here so you can watch them '
      'land.';
  static const String signaturesReadOnly =
      'New requests are created on banksheet.pro — placing signature boxes on a '
      'page needs a big screen. This is where you follow them.';
  static const String auditTrail = 'Audit trail';
  static const String noAuditEvents = 'No events recorded yet';
  static const String noSignersRecorded = 'No signers recorded';
  static const String signatureDocument = 'Document';
  static const String signatureProvider = 'Provider';
  static const String signingOrder = 'Signing order';
  static const String emailSubject = 'Email subject';
  static const String copiedTo = 'Copied to';
  static const String signedPdfPending =
      'The signed PDF appears here once everyone has signed.';
  static const String declineReason = 'Reason given';
  static const String signingLinkExpired = 'Signing link expired';
  static const String filterAwaiting = 'Awaiting';
  static const String filterCompleted = 'Completed';
  static const String filterDeclined = 'Declined';
  static const String signerPending = 'Not opened yet';
  static const String signerInvited = 'Invited';
  static const String signerViewed = 'Opened';
  static const String signerSigned = 'Signed';
  static const String signerDeclined = 'Declined';
  static const String sentOn = 'Sent';
  static const String firstOpened = 'First opened';
  static const String completedOn = 'Completed';
  static const String expiresOn = 'Expires';
  static const String lastActivity = 'Last activity';

  static String signerProgress(int signed, int total) =>
      '$signed of $total signed';

  static String signatureRequestCount(int count) =>
      count == 1 ? '1 request' : '$count requests';

  static String eventCount(int count) =>
      count == 1 ? '1 event' : '$count events';

  // ---------------------------------------------------------------- exports
  static const String exports = 'Export archive';
  static const String exportsSubtitle = 'Everything you have exported';
  static const String share = 'Share';

  // -- archive, downloads and sharing (content agent) ----------------------
  static const String noExports = 'No exports yet';
  static const String noExportsBody =
      'Export a processed document and the spreadsheet is kept here, ready to '
      'download again.';
  static const String downloadFile = 'Download';
  static const String open = 'Open';
  static const String downloading = 'Downloading…';
  static const String savedToDevice = 'Saved to your device.';
  static const String couldNotOpenFile =
      'No app on this device can open that file. It is saved in your files.';
  static const String fileUnavailableBody =
      'This file has been removed from the server. Generate it again from the '
      'document it came from.';
  static const String exportUnknownFormat = 'File';
  static const String today = 'Today';
  static const String yesterday = 'Yesterday';
  static const String undated = 'Undated';

  static String recordCount(int count) =>
      count == 1 ? '1 record' : '$count records';

  static String exportCount(int count) =>
      count == 1 ? '1 export' : '$count exports';

  // --------------------------------------------------- extraction profiles
  static const String profiles = 'Extraction profiles';
  static const String profilesSubtitle = 'How each bank statement is read';
  static const String noProfiles = 'No profiles yet';
  static const String noProfilesBody =
      'Without a profile we fall back to generic parsing. Build one on '
      'banksheet.pro with a sample statement beside the rules.';
  static const String profilesAuthoredOnWeb =
      'Profiles are built on banksheet.pro, where a sample statement sits next '
      'to the rules. Here you can review one and switch it on or off.';
  static const String activeOnly = 'Active only';
  static const String profileActivated = 'Profile switched on.';
  static const String profileDeactivated = 'Profile switched off.';
  static const String profileActive = 'Active';
  static const String profileInactive = 'Off';
  static const String lastMatched = 'Last matched';
  static const String neverMatched = 'Never matched';
  static const String sampleOnFile = 'Sample statement on file';
  static const String sectionIdentity = 'Identity';
  static const String sectionRegionFormats = 'Region and formats';
  static const String sectionRecognition = 'Statement recognition';
  static const String sectionColumnMapping = 'Column mapping';
  static const String advanced = 'Advanced';
  static const String rulesMatch = 'Match rules';
  static const String rulesColumn = 'Column rules';
  static const String rulesNormalization = 'Normalisation';
  static const String rulesPostProcessing = 'Post-processing';
  static const String rulesBuilder = 'Builder state';
  static const String rawRulesBody =
      'Exactly what the parser runs on. Read-only here.';
  static const String noRules = 'No rules recorded';
  static const String noRulesBody =
      'This profile has no parsing rules stored, so it can never match a '
      'statement. Open it on banksheet.pro to build them.';
  static const String country = 'Country';
  static const String statementLanguage = 'Language';
  static const String dateFormat = 'Date format';
  static const String numberFormat = 'Number format';
  static const String decimalSeparator = 'Decimal separator';
  static const String dayFirst = 'Day before month';
  static const String statementKeywords = 'Statement keywords';
  static const String headerKeywords = 'Header keywords';
  static const String columnHeaders = 'Column headers';
  static const String tableStartKeywords = 'Table starts at';
  static const String tableEndKeywords = 'Table ends at';
  static const String ignoredLines = 'Ignored lines';
  static const String cleanupRules = 'Description cleanup';
  static const String amountColumn = 'Amount';
  static const String amountMode = 'Amount columns';
  static const String amountModeSeparate = 'Separate money in and money out';
  static const String amountModeSingle = 'One signed amount column';
  static const String amountPattern = 'Amount pattern';
  static const String inferFromBalance = 'Infer the sign from the balance';
  static const String mergeMultiline = 'Merge wrapped rows';
  static const String documentsParsed = 'Documents parsed';
  static const String rowsExtractedTotal = 'Rows extracted';
  static const String yes = 'Yes';
  static const String no = 'No';

  static String profileCount(int count) =>
      count == 1 ? '1 profile' : '$count profiles';

  // ---------------------------------------------------------------- billing
  static const String billing = 'Plan & billing';
  static const String currentPlan = 'Current plan';
  static const String upgrade = 'Upgrade';
  static const String choosePlan = 'Choose a plan';
  static const String restorePurchases = 'Restore purchases';
  static const String manageSubscription = 'Manage subscription';
  static const String autoRenewNotice =
      'Your subscription renews automatically each period until you cancel. '
      'Cancel any time from your store account — cancelling at least 24 hours '
      'before the renewal date stops the next charge.';
  static const String managedOnWeb = 'Managed on banksheet.pro';
  static const String managedOnWebBody =
      'This workspace is billed by card on the website. Manage or change the '
      'plan there — purchasing here would charge you twice.';
  static const String managedByStore = 'Managed by your app store';
  static const String purchaseSuccess = 'Your plan is active. Enjoy.';
  static const String restoreNothing = 'No previous purchase found on this account.';
  static const String termsLink = 'Terms of Service';
  static const String privacyLink = 'Privacy Policy';

  // Appended by the billing feature. Append only — new billing strings go at
  // the end of this block so a concurrent edit elsewhere cannot conflict.
  static const String billedByAppStore = 'App Store';
  static const String billedByGooglePlay = 'Google Play';
  static const String billedByWebsite = 'banksheet.pro';
  static const String billedByNobody = 'Free plan';
  static const String renewsOn = 'Renews';
  static const String accessUntil = 'Access until';
  static const String autoRenewOn = 'Auto-renew on';
  static const String autoRenewOff = 'Auto-renew off';
  static const String allowanceResets = 'Allowances reset';
  static const String planIncludes = 'What you get';
  static const String periodMonthly = 'Monthly subscription';
  static const String periodYearly = 'Yearly subscription';
  static const String priceFromStore =
      'Charged by your store, in your local currency.';
  static const String storeUnavailableTitle = 'Purchases are unavailable';
  static const String storeUnavailableBody =
      'This device cannot reach the App Store or Google Play right now, so '
      'plans cannot be bought here. You can still subscribe on banksheet.pro.';
  static const String storeProductsMissing =
      'Some plans could not be loaded from the store. Pull down to try again.';
  static const String purchaseCancelled =
      'Purchase cancelled. Nothing was charged.';
  static const String purchasePending =
      'Your store is still confirming the payment. This can take a moment.';
  static const String verifyingTitle = 'Confirming your purchase';
  static const String verifyingBody =
      'Keep the app open — closing it now could delay your plan. This takes a '
      'few seconds.';
  static const String purchaseFailedTitle = 'Purchase not completed';
  static const String purchaseWillRetry =
      'Your purchase is safe. The app will finish confirming it the next time '
      'you open it.';
  static const String purchaseActiveEverywhere =
      'It is active on this phone and on banksheet.pro — sign in there with the '
      'same account and the new limits are already applied.';
  static const String restoreRunning = 'Checking your store account…';
  static const String restoreBody =
      'Bought a plan with this Apple ID or Google account before? Restore it '
      'here.';
  static const String restoreSomeFailed =
      'Some receipts could not be restored. Contact support with your order id.';
  static const String enterpriseTitle = 'Need more than Professional?';
  static const String enterpriseBody =
      'Enterprise is priced per workspace, with SSO, custom integrations and a '
      'named contact. Tell us what you need and we will answer.';
  static const String talkToUs = 'Talk to us';
  static const String currentPlanChip = 'Your plan';
  static const String choosePlanBody =
      'Upgrade instantly. Your new limits apply here and on the website.';
  static const String manageSubscriptionBody =
      'Cancel or change your subscription in your store account — the store '
      'holds the payment method, so it is the only place it can be done.';
  static const String planNotInStore =
      'Not available from your store on this device.';
  static const String legalAgree = 'By subscribing you agree to:';
  static const String confirmPurchase = 'Continue to payment';
  static String getPlan(String plan) => 'Get $plan';
  static String planActiveNow(String plan) => '$plan is active';
  static String restoredCount(int count) =>
      count == 1 ? '1 purchase restored' : '$count purchases restored';

  // -- appended by the billing feature, second pass -------------------------
  // `billingSubtitle` used to live in this block and collided with the More
  // hub's own `billingSubtitle` further down, which is a duplicate declaration
  // and does not compile. The hub's copy is the one other features reference,
  // so the billing screen carries its own name instead.
  static const String billingHeroTitle =
      'Your plan, your usage, your receipts';
  static const String usageApiDocuments = 'API documents';
  static const String usageEmployees = 'Team members';
  static const String usageExtractionProfiles = 'Extraction profiles';
  static const String subscriptionPastDue =
      'The last payment did not go through. Update your payment method in your '
      'store account to keep this plan.';
  static const String storeCheckingProducts = 'Reading prices from the store…';
  static const String purchaseInProgress =
      'A purchase is already in progress on this device.';
  static const String restoreFailedTitle = 'Nothing could be restored';
  static const String planBenefitsFromStore =
      'Full plan details are on banksheet.pro.';
  static String storageIncluded(String size) => '$size of storage included';

  // --------------------------------------------------------------- settings
  static const String settings = 'Settings';
  static const String profile = 'Profile';
  static const String changePassword = 'Change password';
  static const String language = 'Language';
  static const String apiKeys = 'API keys';
  static const String apiKeysSubtitle = 'For the developer API';
  static const String about = 'About';
  static const String deleteAccount = 'Delete account';
  static const String deleteAccountBody =
      'This permanently deletes your account and every document in it. '
      'This cannot be undone.';
  static const String deleteAccountConfirm = 'Delete my account';
  static const String version = 'Version';
  static const String openWebsite = 'Open banksheet.pro';
  static const String contactSupport = 'Contact support';

  // -- the More hub (settings agent) ---------------------------------------
  static const String more = 'More';
  static const String moreHeroTitle = 'Everything else, one tap away';
  static const String sectionWork = 'Work';
  static const String sectionTools = 'Tools';
  static const String sectionAccount = 'Account';
  static const String sectionPreferences = 'Preferences';
  static const String sectionDeveloper = 'Developer';
  static const String sectionSupport = 'Support';
  static const String workspaceLabel = 'Workspace';
  static const String conversionsSubtitle = 'Files you have converted';
  static const String billingSubtitle = 'Plan, allowance and payment';
  static const String settingsSubtitle = 'Profile, language, API keys';

  // -- the settings list (settings agent) ----------------------------------
  static const String settingsHeroTitle = 'Your account and your workspace';
  static const String profileSubtitle = 'Your name and email address';
  static const String changePasswordSubtitle = 'Use a long, unique password';
  static const String languageSubtitle = 'For emails and generated files';
  static const String aboutSubtitle = 'Version, legal and diagnostics';
  static const String signOutConfirmBody =
      'You will need to sign in again on this device. Nothing is deleted.';
  static const String dangerZone = 'Danger zone';

  // -- edit profile ---------------------------------------------------------
  static const String editProfile = 'Edit profile';
  static const String editProfileSubtitle =
      'The name and address we use on emails and generated documents.';
  static const String profileSaved = 'Profile updated.';
  static const String emailChangeWarning =
      'Changing your email address means it has to be verified again. We will '
      'send a confirmation link to the new address, and the old one stops '
      'being used.';
  static const String emailNotVerified =
      'This address has not been verified yet.';
  static const String nothingChanged = 'Nothing has changed yet.';

  // -- change password ------------------------------------------------------
  static const String changePasswordIntro =
      'Choose something you do not use anywhere else.';
  static const String otherDevicesWillSignOut =
      'Changing your password signs out every other device. This one stays '
      'signed in.';
  static const String passwordChangedSignedOutOthers =
      'Password changed. Your other devices have been signed out.';
  static const String passwordChecklistTitle = 'A strong password has';
  static const String ruleLength = 'At least 8 characters';
  static const String ruleMixedCase = 'Upper and lower case letters';
  static const String ruleDigit = 'A number';
  static const String ruleSymbol = 'A symbol, such as ! or #';

  // -- language -------------------------------------------------------------
  static const String languageIntro =
      'This sets the language of your emails and of anything the server '
      'renders for you.';
  static const String languageAppEnglishNotice =
      "The app's own labels stay in English for now — your choice applies to "
      'emails and to content the server generates.';
  static const String languageSaved = 'Language updated.';
  static const String localesFallbackNotice =
      'The language list could not be loaded, so the built-in list is shown.';

  // -- API keys -------------------------------------------------------------
  static const String apiKeysIntro =
      'API keys let your own software submit documents to BankSheet Pro.';
  static const String apiKeysForbiddenTitle = 'Owners and admins only';
  static const String apiKeysForbiddenBody =
      'A key carries the whole workspace allowance and can read every document '
      'sent through it, so only the owner or a company admin can manage keys. '
      'Ask one of them to create a key for you.';
  static const String noApiKeys = 'No API keys yet';
  static const String noApiKeysBody =
      'Create a key to let your own software send documents through the API.';
  static const String createApiKey = 'Create a key';
  static const String apiKeyName = 'Key name';
  static const String apiKeyNameHint =
      'Where it will be used, e.g. Billing server';
  static const String apiKeyCreated = 'API key created.';
  static const String apiKeyRevealTitle = 'Copy your key now';
  static const String apiKeyRevealBody =
      'Store it somewhere safe. If you lose it you will have to create another '
      'one.';
  static const String apiKeyRevealWarning =
      'This is the only time this key is shown. You will not see it again.';
  static const String copyKey = 'Copy key';
  static const String apiKeyCopied = 'Key copied.';
  static const String revokeKey = 'Revoke';
  static const String revokeKeyTitle = 'Revoke this key?';
  static const String revokeKeyBody =
      'Any software using it stops working immediately. A revoked key cannot '
      'be restored — create a new one instead.';
  static const String apiKeyRevoked = 'Key revoked.';
  static const String revoked = 'Revoked';
  static const String apiEnvironmentTest = 'Test';
  static const String apiEnvironmentLive = 'Live';
  static const String lastUsed = 'Last used';
  static const String neverUsed = 'Never used';
  static const String created = 'Created';
  static const String apiDocumentsThisPeriod = 'API documents this period';

  // -- about ----------------------------------------------------------------
  static const String build = 'Build';
  static const String legal = 'Legal';
  static const String diagnostics = 'Diagnostics';
  static const String diagnosticsBody =
      'Recent activity recorded on this device. Nothing leaves the phone on '
      'its own — copy it into a support message only if we ask for it.';
  static const String noDiagnostics = 'Nothing has been logged yet.';
  static const String copyDiagnostics = 'Copy diagnostics';
  static const String diagnosticsCopied = 'Diagnostics copied.';

  // -- delete account -------------------------------------------------------
  static const String deleteAccountWhat = 'What gets deleted';
  static const String deleteAccountPointAccount =
      'Your account, your name and your email address';
  static const String deleteAccountPointDocuments =
      'Every document, extracted row and export in your workspace';
  static const String deleteAccountPointContent =
      'Templates, generated PDFs and signature requests';
  static const String deleteAccountPointAccess =
      'API keys, and every device signed in to this account';
  static const String deleteAccountStoreNotice =
      'A subscription bought through the App Store or Google Play is not '
      'cancelled by this. Cancel it in your store account as well.';
  static const String deleteAccountPasswordTitle = 'Confirm with your password';
  static const String deleteAccountPasswordBody =
      'This is permanent and immediate. Enter your current password to delete '
      'the account.';
  static const String accountDeleted = 'Your account has been deleted.';

  static String apiKeyCount(int count) => count == 1 ? '1 key' : '$count keys';

  // -- appended by the settings feature, second pass ------------------------
  // Append only: new settings strings go at the end of this block so a
  // concurrent edit in another section cannot conflict with one here.
  static const String conversionHistory = 'Conversion history';
  static const String passwordManagedByProvider =
      'This account signs in with Google, so there is no password to change '
      'here. Manage it in your Google account.';
  static const String minimumSupportedVersion = 'Minimum supported version';
  static const String apiNotIncludedInPlan =
      'API access is not part of this plan. Keys keep working until the free '
      'trial allowance runs out.';

  static String apiTrialRemaining(int count) => count == 1
      ? '1 trial document left'
      : '$count trial documents left';

  // ---------------------------------------------------------------- general
  static const String save = 'Save';
  static const String cancel = 'Cancel';
  static const String close = 'Close';
  static const String delete = 'Delete';
  static const String confirm = 'Confirm';
  static const String tryAgain = 'Try again';
  static const String search = 'Search';
  static const String filter = 'Filter';
  static const String all = 'All';
  static const String loading = 'Loading…';
  static const String offline = 'You are offline. Showing saved data.';
  static const String somethingWentWrong = 'Something went wrong';
  static const String noConnection = 'No connection';
  static const String noConnectionBody =
      'Check your network and pull down to refresh.';
  static const String updateRequired = 'Update required';
  static const String updateRequiredBody =
      'This version of the app is no longer supported. Update to continue.';
  static const String updateNow = 'Update now';
  static const String quotaReached = 'Monthly limit reached';
  static const String seePlans = 'See plans';
  static const String copied = 'Copied';
  static const String required = 'Required';
  static const String optional = 'Optional';
  static const String clear = 'Clear';
  static const String copy = 'Copy';
  static const String done = 'Done';
  static const String continueLabel = 'Continue';

  // -------------------------------------------------- greeting by clock hour
  static String greeting(DateTime now) {
    if (now.hour < 12) {
      return goodMorning;
    }
    if (now.hour < 18) {
      return goodAfternoon;
    }
    return goodEvening;
  }
}
