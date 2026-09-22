import 'package:flutter/material.dart';

Locale resolveDeviceLocale(
  List<Locale>? preferred,
  Iterable<Locale> supported,
) {
  // Follow the primary device language; unsupported languages use English.
  return Locale(preferred?.firstOrNull?.languageCode == 'ar' ? 'ar' : 'en');
}

String languageOf(BuildContext context) =>
    Localizations.localeOf(context).languageCode;
String tr(BuildContext context, String text) =>
    translate(text, languageOf(context));
String translate(String text, String language) {
  if (language != 'ar') return text;
  final exact =
      arabic[text] ??
      arabic.entries
          .where(
            (e) =>
                !e.key.contains('{0}') &&
                e.key.toLowerCase() == text.toLowerCase(),
          )
          .firstOrNull
          ?.value;
  if (exact != null) return exact;
  for (final entry in arabic.entries.where((e) => e.key.contains('{0}'))) {
    final parts = entry.key.split(RegExp(r'\{\d+\}'));
    final pattern = '^${parts.map(RegExp.escape).join('(.*?)')}\$';
    final match = RegExp(pattern, dotAll: true).firstMatch(text);
    if (match != null) {
      var result = entry.value;
      for (var i = 1; i <= match.groupCount; i++) {
        result = result.replaceAll(
          '{${i - 1}}',
          translate(match.group(i)!, language),
        );
      }
      return result;
    }
  }
  if (text.contains(' · ')) {
    return text
        .split(' · ')
        .map((part) => translate(part, language))
        .join(' · ');
  }
  return text;
}

/// Localizes presentation only. Stored identifiers and user input are untouched.
class AppText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  const AppText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });
  @override
  Widget build(BuildContext context) => Text(
    tr(context, data),
    style:
        languageOf(context) == 'ar'
            ? (style ?? const TextStyle()).copyWith(
              letterSpacing: 0,
              height: style?.height ?? 1.5,
            )
            : style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
  );
}

const arabic = <String, String>{
  'Tadbeer': 'تدبير',
  'Tadbeer • Money Management': 'تدبير • إدارة الأموال',
  'Up to two matching listings. Prices in different currencies are not ranked against each other.':
      'حتى عرضين مطابقين. لا تتم المفاضلة بين الأسعار بعملات مختلفة.',
  'The service returned an unexpected response. Please try again later.':
      'أعادت الخدمة استجابة غير متوقعة. يرجى المحاولة لاحقاً.',
  'The service is not configured correctly. Please contact support.':
      'الخدمة غير مهيأة بشكل صحيح. يرجى التواصل مع الدعم.',
  'Invoice analysis is temporarily unavailable. Please try again later.':
      'تحليل الفواتير غير متاح مؤقتاً. يرجى المحاولة لاحقاً.',
  'Price search is temporarily unavailable. Please try again later.':
      'البحث عن الأسعار غير متاح مؤقتاً. يرجى المحاولة لاحقاً.',
  'Price search is busy. Please try again later.':
      'خدمة البحث عن الأسعار مشغولة. يرجى المحاولة لاحقاً.',

  'See prices on product cards': 'اطّلع على الأسعار في بطاقات المنتجات',
  'Currency unconfirmed': 'العملة غير مؤكدة',
  'Prices use different or unconfirmed currencies; no combined total is calculated.':
      'الأسعار بعملات مختلفة أو غير مؤكدة؛ لا يتم حساب إجمالي موحّد.',
  'Unknown details should stay blank. Original prices are in SAR; listing currencies may differ.':
      'اترك التفاصيل غير المعروفة فارغة. الأسعار الأصلية بالريال السعودي؛ وقد تختلف عملات العروض.',

  'Listed price': 'السعر المدرج',
  'For the required quantity: {0}': 'للكمية المطلوبة: {0}',
  'View product': 'عرض المنتج',
  'Tap a product card to open its supplied link. Check the product and final price before buying.':
      'اضغط على بطاقة المنتج لفتح رابطه المتاح. تحقق من المنتج والسعر النهائي قبل الشراء.',
  'One combined search covers this list. Some items may have no matching results.':
      'يغطي هذه القائمة بحث واحد مجمّع. قد لا تتوفر نتائج مطابقة لبعض العناصر.',
  'Up to two lowest matching listed prices from these search results.':
      'حتى عرضين مطابقين بأقل الأسعار المدرجة ضمن نتائج هذا البحث.',
  'Your selected items use one combined search. Some items may have no matching offers.':
      'تستخدم العناصر المحددة بحثاً واحداً مجمّعاً. قد لا تتوفر عروض مطابقة لبعضها.',
  'This list is too long for one search. Select fewer items and try again.':
      'القائمة طويلة جداً لبحث واحد. حدد عناصر أقل وحاول مجدداً.',
  'A photo, screenshot or invoice can become a shopping list. Tap a product card to open its link.':
      'يمكن تحويل صورة أو لقطة شاشة أو فاتورة إلى قائمة تسوق. اضغط على بطاقة منتج لفتح رابطه.',

  'Equivalent quantity including known shipping':
      'كمية مكافئة تشمل تكلفة الشحن المعروفة',
  'Equivalent quantity; shipping not provided':
      'كمية مكافئة؛ تكلفة الشحن غير متوفرة',
  'Listed offer price; original quantity unknown':
      'سعر العرض المدرج؛ الكمية الأصلية غير معروفة',
  '{0}; extra quantity must be purchased': '{0}؛ يجب شراء كمية إضافية',
  'Shopping estimate for the requested number of listed offers; brands, sizes, and packs may differ.':
      'تقدير تسوق لعدد العروض المطلوب؛ قد تختلف العلامات التجارية والأحجام والعبوات.',
  'Listed offer price; enter a quantity for a shopping estimate.':
      'سعر العرض المدرج؛ أدخل كمية للحصول على تقدير للتسوق.',
  '{0} Whole listed packs must be purchased.':
      '{0} يجب شراء العبوات المدرجة كاملة.',
  '{0} Shipping not provided.': '{0} تكلفة الشحن غير متوفرة.',

  'Search by product name': 'البحث باسم المنتج',
  'Shopping list': 'قائمة التسوق',
  'What is on your list?': 'ماذا تريد أن تشتري؟',
  'What are you looking for?': 'ما الذي تبحث عنه؟',
  'Paste a message, a checklist or a list of things you want to buy. Include quantities, brands and sizes when you know them.':
      'ألصق رسالة أو قائمة بالأشياء التي تريد شراءها. أضف الكميات والعلامات التجارية والأحجام إن كنت تعرفها.',
  'Type the product name. Add the brand, model, capacity or size for more useful results.':
      'اكتب اسم المنتج. أضف العلامة التجارية أو الطراز أو السعة أو الحجم للحصول على نتائج أنسب.',
  'Paste your list': 'ألصق قائمتك',
  '2 bottles of Almarai milk 2L\nCoffee beans 250g\nUSB-C charger 30W':
      'عبوتان من حليب المراعي ٢ لتر\nحبوب قهوة ٢٥٠ غرام\nشاحن USB-C بقدرة ٣٠ واط',
  'We organize the list first. You can edit every item before any price search starts.':
      'ننظّم القائمة أولاً. يمكنك تعديل كل عنصر قبل بدء البحث عن الأسعار.',
  'Review the name and optional current price before searching stores.':
      'راجع الاسم والسعر الحالي الاختياري قبل البحث في المتاجر.',
  'Organizing your shopping list…': 'جارٍ تنظيم قائمة التسوق…',
  'Preparing your product…': 'جارٍ تجهيز المنتج…',
  'Review my list': 'مراجعة قائمتي',
  'Review product': 'مراجعة المنتج',
  'Shopping searches do not add expenses. Your budget changes only when you save an expense.':
      'البحث للتسوق لا يضيف مصروفات. تتغير ميزانيتك فقط عند حفظ مصروف.',
  'Paste your shopping list first.': 'ألصق قائمة التسوق أولاً.',
  'Could not prepare your products. Try again.':
      'تعذّر تجهيز منتجاتك. حاول مجدداً.',
  'Search a product by name, paste your shopping list, or import a list image. Review the items, then find online stores.':
      'ابحث عن منتج باسمه، أو ألصق قائمة التسوق، أو استورد صورة قائمة. راجع العناصر ثم اعثر على متاجر إلكترونية.',
  'Paste a shopping list': 'لصق قائمة تسوق',
  'Import list or invoice': 'استيراد قائمة أو فاتورة',
  'Import list or invoice image': 'استيراد صورة قائمة أو فاتورة',
  'A photo, screenshot or invoice can become a shopping list. Tap a result to visit the online shop.':
      'حوّل صورة أو لقطة شاشة أو فاتورة إلى قائمة تسوق. اضغط على نتيجة لزيارة المتجر الإلكتروني.',
  'Scan Invoice and add expense': 'مسح فاتورة وإضافة مصروف',
  'Shopping list results': 'نتائج قائمة التسوق',
  'Estimated shopping total: {0}': 'إجمالي التسوق التقديري: {0}',
  'Capture the full shopping list or invoice with clear item names and quantities.':
      'صوّر قائمة التسوق أو الفاتورة كاملة مع وضوح أسماء العناصر وكمياتها.',
  'Turn a list into shopping options': 'حوّل القائمة إلى خيارات تسوق',
  'Reading your list…': 'جارٍ قراءة قائمتك…',
  'Read list or invoice': 'قراءة القائمة أو الفاتورة',
  'Choose list or invoice image': 'اختيار صورة قائمة أو فاتورة',
  'These are items you want to buy. Prices are optional. Generic items show shopping options, not verified equivalents.':
      'هذه عناصر تريد شراءها. الأسعار اختيارية. تعرض العناصر العامة خيارات تسوق دون تأكيد أنها منتجات مكافئة.',
  'Check the extracted items and quantities against your original list or image.':
      'راجع العناصر والكميات المستخرجة وقارنها بقائمتك أو صورتك الأصلية.',
  'Shopping results': 'نتائج التسوق',
  'Estimated shopping total': 'إجمالي التسوق التقديري',
  'Found offers for {0} of {1} items': 'عُثر على عروض لـ {0} من أصل {1} عناصر',
  'Tap an item to open its online shop. Check the exact option, quantity and final price before buying.':
      'اضغط على عنصر لفتح متجره الإلكتروني. تحقق من الخيار المحدد والكمية والسعر النهائي قبل الشراء.',
  'Partial estimate. Items without a usable price or quantity are not included.':
      'تقدير جزئي. لا يشمل العناصر التي لا تتوفر لها أسعار أو كميات قابلة للاستخدام.',
  'Some quantities are unknown. Listed prices may represent one pack rather than your full requirement.':
      'بعض الكميات غير معروفة. قد تمثل الأسعار المعروضة عبوة واحدة وليس كامل احتياجك.',
  'Shopping options are suggestions for your list. A broad result is not a verified equivalent, and an estimate is not a saving.':
      'خيارات التسوق اقتراحات لقائمتك. النتيجة العامة ليست بديلاً مكافئاً مؤكداً، والتقدير ليس توفيراً.',
  'Your items': 'عناصرك',
  'No shopping options found': 'لم يُعثر على خيارات تسوق',
  'Shopping option': 'خيار تسوق',
  'Broad search result. Check brand, size and pack count; this is not a verified equivalent.':
      'نتيجة بحث عامة. تحقق من العلامة التجارية والحجم وعدد العبوات؛ ليست بديلاً مكافئاً مؤكداً.',
  'Search result': 'نتيجة بحث',
  'View shopping listing': 'عرض صفحة التسوق',
  'Open online shop': 'فتح المتجر الإلكتروني',
  'Finding the online shop…': 'جارٍ العثور على المتجر الإلكتروني…',
  'Your shop link is ready': 'رابط المتجر جاهز',
  'A matching online shop link could not be found. Try another offer.':
      'تعذّر العثور على رابط متجر مطابق. جرّب عرضاً آخر.',
  'Enter a product name or a shopping list within the text limit.':
      'أدخل اسم منتج أو قائمة تسوق ضمن الحد المسموح للنص.',
  'The list could not be read. Paste clearer text or choose a clearer image.':
      'تعذّرت قراءة القائمة. ألصق نصاً أوضح أو اختر صورة أوضح.',

  'Comparison history could not be read. Clear it to save new comparisons. Your expenses are unaffected.':
      'تعذّرت قراءة سجل المقارنات. امسحه لحفظ مقارنات جديدة. لم تتأثر مصروفاتك.',

  'Condition not verified': 'لم يتم التحقق من حالة المنتج',
  'Savings unavailable. Add an original price and quantity, then compare matching offers.':
      'التوفير غير متاح. أضف السعر والكمية الأصليين، ثم قارن العروض المطابقة.',
  'Normalized price: {0}': 'السعر الموحّد: {0}',
  'Original normalized price: {0}': 'السعر الأصلي الموحّد: {0}',
  'liter': 'لتر',
  'item': 'قطعة',

  'This is a total, fee, or payment line, not a product.':
      'هذا بند إجمالي أو رسوم أو دفع، وليس منتجاً.',
  'Add the brand, model, or a more specific product name.':
      'أضف العلامة التجارية أو الطراز أو اسماً أكثر تحديداً للمنتج.',
  'The detected product is uncertain. Review its identity before comparing.':
      'التعرّف على المنتج غير مؤكد. راجع هويته قبل المقارنة.',
  'The search limit was reached; higher-value products were compared first.':
      'تم الوصول إلى حد البحث؛ جرت مقارنة المنتجات الأعلى قيمة أولاً.',
  'No shopping offers were returned for this product.':
      'لم يُعثر على عروض تسوق لهذا المنتج.',
  'No reliable matching alternative was found.':
      'لم يُعثر على بديل مطابق موثوق.',
  'Offers found; enter the original price and quantity to calculate savings.':
      'تم العثور على عروض؛ أدخل السعر والكمية الأصليين لحساب التوفير.',
  'A matching offer could reduce the cost of an equivalent quantity.':
      'قد يخفض عرض مطابق تكلفة كمية مكافئة.',
  'The price difference is below your minimum savings thresholds.':
      'فرق السعر أقل من الحدود الدنيا المحددة للتوفير.',
  'No lower price was found for an equivalent quantity.':
      'لم يُعثر على سعر أقل لكمية مكافئة.',
  'Only SAR prices can be compared.':
      'يمكن مقارنة الأسعار بالريال السعودي فقط.',
  'The price search could not finish. Other successful comparisons are preserved.':
      'تعذّر إكمال البحث عن السعر. تم الاحتفاظ بالمقارنات الأخرى الناجحة.',

  'Smart Price Recommendation': 'توصيات الأسعار الذكية',
  'Smart Savings': 'التوفير الذكي',
  'Shop with clarity': 'تسوّق بوضوح',
  'Find a better price': 'اعثر على سعر أفضل',
  'Same product. Smarter spending.': 'المنتج نفسه. إنفاق أذكى.',
  'Photograph a product or compare the items on your receipt. Review the details, then search Saudi shopping offers.':
      'صوّر منتجاً أو قارن عناصر فاتورتك. راجع التفاصيل، ثم ابحث في عروض التسوق السعودية.',
  'Scan Product': 'مسح منتج',
  'For an invoice, use Compare prices in the review screen. You can still add it to Expenses as usual.':
      'للفاتورة، استخدم «مقارنة الأسعار» في شاشة المراجعة. ويمكنك إضافتها إلى المصروفات كالمعتاد.',
  'Recent comparisons': 'المقارنات الأخيرة',
  'Your comparisons will appear here': 'ستظهر مقارناتك هنا',
  'Your latest 20 comparisons appear here. Potential savings never change your expense balance.':
      'تظهر هنا آخر ٢٠ مقارنة أجريتها. التوفير المحتمل لا يغيّر رصيد مصروفاتك.',
  'Invoice comparison': 'مقارنة فاتورة',
  'Product comparison': 'مقارنة منتج',
  'Potential saving: {0}': 'التوفير المحتمل: {0}',
  'Clear comparison history': 'مسح سجل المقارنات',
  'Clear comparison history?': 'مسح سجل المقارنات؟',
  'This removes comparison history. Your expenses stay saved.':
      'يحذف هذا سجل المقارنات. تبقى مصروفاتك محفوظة.',
  'This comparison is too large to save in history':
      'هذه المقارنة كبيرة جداً لحفظها في السجل',
  'Could not clear comparison history.': 'تعذّر مسح سجل المقارنات.',
  'Compare the same products. Discover potential savings.':
      'قارن المنتجات نفسها واكتشف فرص التوفير.',
  'Find better prices': 'اعثر على أسعار أفضل',
  'Capture the product label, brand, model and package size clearly.':
      'صوّر ملصق المنتج والعلامة التجارية والطراز وحجم العبوة بوضوح.',
  'Find the product. Compare the price.': 'تعرّف على المنتج. قارن السعر.',
  'Identifying product…': 'جارٍ التعرّف على المنتج…',
  'Identify Product': 'التعرّف على المنتج',
  'Choose product image': 'اختيار صورة منتج',
  'Compare prices': 'مقارنة الأسعار',
  'Review products': 'مراجعة المنتجات',
  'Review before searching': 'راجع قبل البحث',
  'Correct names, brand, model, size and pack count. Only selected products will be searched.':
      'صحّح الأسماء والعلامة التجارية والطراز والحجم وعدد وحدات العبوة. سيقتصر البحث على المنتجات المحددة.',
  'Unknown details should stay blank. Price comparisons are for Saudi Arabia in SAR.':
      'اترك التفاصيل غير المعروفة فارغة. المقارنة مخصصة للسعودية بالريال السعودي.',
  'Comparing prices does not save an expense. Return to Review invoice and use Add Expense.':
      'مقارنة الأسعار لا تحفظ مصروفاً. ارجع إلى مراجعة الفاتورة واستخدم «إضافة مصروف».',
  'Some product details could not be read. Check them against the photo.':
      'تعذّرت قراءة بعض تفاصيل المنتجات. راجعها في الصورة.',
  'Photo preview unavailable': 'معاينة الصورة غير متاحة',
  'No products to compare': 'لا توجد منتجات للمقارنة',
  'Add identifiable items in the invoice review first.':
      'أضف أولاً عناصر يمكن التعرّف عليها في مراجعة الفاتورة.',
  'Compare this product': 'مقارنة هذا المنتج',
  'Product name': 'اسم المنتج',
  'Model confidence: {0}% (self-reported)': 'ثقة النموذج: {0}٪ (تقدير ذاتي)',
  'Current price (SAR, optional)': 'السعر الحالي (ريال، اختياري)',
  'Original unit price (SAR)': 'سعر الوحدة الأصلي (ريال)',
  'Original line total (SAR)': 'إجمالي البند الأصلي (ريال)',
  'Identity, size and packaging': 'هوية المنتج وحجمه وتغليفه',
  'Brand': 'العلامة التجارية',
  'Model / generation': 'الطراز / الجيل',
  'Variant / capacity / color': 'النسخة / السعة / اللون',
  'Size / weight / volume': 'الحجم / الوزن / السعة',
  'Size unit': 'وحدة القياس',
  'Units per pack': 'عدد الوحدات في العبوة',
  'Condition': 'الحالة',
  'Unknown': 'غير معروف',
  'new': 'جديد',
  'used': 'مستعمل',
  'refurbished': 'مجدّد',
  'ml': 'مل',
  'l': 'لتر',
  'g': 'غرام',
  'kg': 'كغ',
  'unit': 'وحدة',
  'Searching matching offers…': 'جارٍ البحث عن عروض مطابقة…',
  'Confirm and compare prices': 'تأكيد ومقارنة الأسعار',
  'Search starts only when you confirm. Product details are sent through your server to shopping search.':
      'يبدأ البحث بعد تأكيدك فقط. تُرسل تفاصيل المنتج عبر خادمك إلى محرك بحث التسوق.',
  'Select at least one product to compare.':
      'حدد منتجاً واحداً على الأقل للمقارنة.',
  'Results are available, but history could not be saved.':
      'النتائج متاحة، لكن تعذّر حفظ السجل.',
  'Price search failed. Try again.': 'فشل البحث عن الأسعار. حاول مجدداً.',
  'Enter a product name.': 'أدخل اسم المنتج.',
  'Enter positive quantities, sizes and prices, or leave unknown values blank.':
      'أدخل قيماً موجبة للكميات والأحجام والأسعار، أو اترك القيم غير المعروفة فارغة.',
  'Units per pack must be a whole number.':
      'يجب أن يكون عدد الوحدات في العبوة عدداً صحيحاً.',
  'Enter both a size and its unit, or leave both blank.':
      'أدخل الحجم ووحدته معاً، أو اتركهما فارغين.',
  'Time unavailable': 'الوقت غير متاح',
  'Saved comparison. These are historical prices, not a live quote.':
      'مقارنة محفوظة. هذه أسعار سابقة وليست عرضاً مباشراً.',
  'Potential saving': 'التوفير المحتمل',
  'You could save {0}%': 'يمكنك توفير {0}٪',
  'Original invoice total': 'إجمالي الفاتورة الأصلي',
  'Current price': 'السعر الحالي',
  'Comparable item total': 'إجمالي العناصر القابلة للمقارنة',
  'Alternative total for compared items': 'الإجمالي البديل للعناصر المقارنة',
  '{0} of {1} items compared': 'تمت مقارنة {0} من أصل {1} عناصر',
  'Partial comparison: unpriced or unmatched items, tax and fees are not savings.':
      'مقارنة جزئية: العناصر غير المسعّرة أو غير المطابقة والضريبة والرسوم لا تُحسب كتوفير.',
  'Potential savings are estimates, not money already saved. Match scores are comparison rules, not a probability of accuracy.':
      'التوفير المحتمل تقديري وليس مالاً تم توفيره فعلاً. درجات المطابقة ناتجة عن قواعد مقارنة وليست احتمالاً للدقة.',
  'Check the exact product, pack quantity, final tax, delivery cost and stock at the store. Shipping and availability may be unverified.':
      'تحقق لدى المتجر من المنتج وكمية العبوة والضريبة النهائية وتكلفة التوصيل والمخزون. قد لا تكون بيانات الشحن والتوفر مؤكدة.',
  'Some searches were unavailable or skipped. Results cover only comparable items.':
      'تعذّرت بعض عمليات البحث أو تم تخطيها. تشمل النتائج العناصر القابلة للمقارنة فقط.',
  'Product comparisons': 'مقارنات المنتجات',
  'No reliable cheaper alternative found.': 'لم يُعثر على بديل أرخص موثوق.',
  'Try a clearer product name with brand, model and size.':
      'جرّب اسماً أوضح مع العلامة التجارية والطراز والحجم.',
  'Unknown product': 'منتج غير معروف',
  'Original line total: {0}': 'إجمالي البند الأصلي: {0}',
  'Original unit price: {0}': 'سعر الوحدة الأصلي: {0}',
  'Quantity: {0}': 'الكمية: {0}',
  'No significant saving': 'لا يوجد توفير ملحوظ',
  '{0}% cheaper': 'أرخص بنسبة {0}٪',
  'Other offers': 'عروض أخرى',
  'Cached search results': 'نتائج بحث محفوظة مؤقتاً',
  'Best matching offer': 'أفضل عرض مطابق',
  'Unknown store': 'متجر غير معروف',
  'Offer unit price: {0}': 'سعر وحدة العرض: {0}',
  'Purchase quantity: {0}': 'كمية الشراء: {0}',
  'Quantity adjusted: buying whole packs may provide more than the original quantity.':
      'تم تعديل الكمية: شراء عبوات كاملة قد يوفر أكثر من الكمية الأصلية.',
  'Normalized: {0} / {1}': 'السعر الموحّد: {0} / {1}',
  'Original normalized: {0} / {1}': 'السعر الأصلي الموحّد: {0} / {1}',
  'Match: {0} ({1})': 'المطابقة: {0} ({1})',
  'Store listing rating: {0} · Reviews: {1}':
      'تقييم العرض: {0} · المراجعات: {1}',
  'Reported shipping included in comparison':
      'تكلفة الشحن المعلنة مشمولة في المقارنة',
  'Shipping cost not verified': 'لم يتم التحقق من تكلفة الشحن',
  'View Deal': 'عرض الصفقة',
  'Could not open the deal. Try again.': 'تعذّر فتح الصفقة. حاول مجدداً.',
  'Exact Match': 'مطابقة تامة',
  'Strong Match': 'مطابقة قوية',
  'Similar Product': 'منتج مشابه',
  'Excellent Saving': 'توفير ممتاز',
  'Good Saving': 'توفير جيد',
  'Small Saving': 'توفير بسيط',
  'No Better Price Found': 'لم يُعثر على سعر أفضل',
  'Shopping search is unavailable. Your reviewed products are still here.':
      'بحث التسوق غير متاح. لا تزال المنتجات التي راجعتها محفوظة هنا.',
  'Check the product names, quantities, sizes and prices before searching.':
      'تحقق من أسماء المنتجات والكميات والأحجام والأسعار قبل البحث.',
  'Price comparisons currently support SAR invoices only. No currency conversion is performed.':
      'تدعم مقارنة الأسعار حالياً الفواتير بالريال السعودي فقط. لا يجري تحويل العملات.',
  'The product could not be identified. Try a clearer photo of its label.':
      'تعذّر التعرّف على المنتج. جرّب صورة أوضح لملصقه.',
  'Price search timed out. Try again shortly.':
      'انتهت مهلة البحث عن الأسعار. حاول بعد قليل.',
  'Review your products before starting the price search.':
      'راجع منتجاتك قبل بدء البحث عن الأسعار.',

  'Opening photo picker…': 'جارٍ فتح الصور…',
  'Capture the whole receipt with clear text and all totals visible.':
      'صوّر الفاتورة كاملة مع وضوح النص وجميع المجاميع.',
  'Your invoice, organized': 'فاتورتك، مرتبة',
  'Preview your photo before sending it to the analysis server.':
      'راجع الصورة قبل إرسالها إلى خادم التحليل.',
  'Photo preview': 'معاينة الصورة',
  'Analyzing invoice…': 'جارٍ تحليل الفاتورة…',
  'The analysis model may take a few minutes. Keep this screen open.':
      'قد يستغرق نموذج التحليل بضع دقائق. أبقِ هذه الشاشة مفتوحة.',
  'Analyze Invoice': 'تحليل الفاتورة',
  'Analyze Again': 'إعادة التحليل',
  'Retake Photo': 'إعادة التصوير',
  'Invoice added to expenses': 'تمت إضافة الفاتورة إلى المصروفات',
  'Your photo is sent to the analysis server. You review every field before anything is saved.':
      'تُرسل الصورة إلى خادم التحليل. تراجع جميع الحقول قبل حفظ أي شيء.',
  'Could not open the camera or photo library. Check permissions.':
      'تعذّر فتح الكاميرا أو مكتبة الصور. تحقّق من الأذونات.',
  'Could not read the selected image. Try another photo.':
      'تعذّرت قراءة الصورة المحددة. جرّب صورة أخرى.',
  'Could not connect to the invoice analysis server.':
      'تعذّر الاتصال بخادم تحليل الفواتير.',
  'Analysis timed out. Try a smaller, clearer photo.':
      'انتهت مهلة التحليل. جرّب صورة أصغر وأوضح.',
  'The server is analyzing another invoice. Try again shortly.':
      'يحلّل الخادم فاتورة أخرى. حاول بعد قليل.',
  'Choose a JPG or PNG image.': 'اختر صورة بصيغة JPG أو PNG.',
  'Invoice could not be read. Please retake the photo.':
      'تعذّرت قراءة الفاتورة. أعد تصويرها.',
  'AI returned an invalid result. Please analyze the invoice again.':
      'أعاد الذكاء الاصطناعي نتيجة غير صالحة. أعد تحليل الفاتورة.',
  'AI analysis failed. Please try again.':
      'فشل تحليل الذكاء الاصطناعي. حاول مجدداً.',
  'Analysis was incomplete. Try a clearer photo with fewer items.':
      'التحليل غير مكتمل. جرّب صورة أوضح بعدد أقل من البنود.',
  'Review invoice': 'مراجعة الفاتورة',
  'Check every field against the photo. Missing information stays blank.':
      'طابق كل حقل مع الصورة. تبقى المعلومات المفقودة فارغة.',
  'Some fields may be missing or amounts may not match. Check the whole invoice before saving.':
      'قد تكون بعض الحقول مفقودة أو المبالغ غير متطابقة. راجع الفاتورة كاملة قبل الحفظ.',
  'Merchant Name': 'اسم التاجر',
  'Invoice Number': 'رقم الفاتورة',
  'Date (YYYY-MM-DD)': 'التاريخ (YYYY-MM-DD)',
  'Enter a valid invoice date, no later than today':
      'أدخل تاريخ فاتورة صالحاً لا يتجاوز اليوم',
  'Invoice currency must match your account ({0}).':
      'يجب أن تطابق عملة الفاتورة عملة حسابك ({0}).',
  'No currency conversion is performed. Use an invoice in your account currency.':
      'لا يُجرى تحويل للعملة. استخدم فاتورة بعملة حسابك.',
  'Subtotal': 'المجموع الفرعي',
  'Tax': 'الضريبة',
  'Discount': 'الخصم',
  'Total': 'الإجمالي',
  'Invoice items': 'بنود الفاتورة',
  'No invoice items were detected.': 'لم يتم اكتشاف بنود في الفاتورة.',
  'You can add items manually or save the reviewed invoice total.':
      'يمكنك إضافة البنود يدوياً أو حفظ إجمالي الفاتورة بعد مراجعته.',
  'Item {0}': 'البند {0}',
  'Remove item': 'حذف البند',
  'Item name': 'اسم البند',
  'Quantity': 'الكمية',
  'Unit price': 'سعر الوحدة',
  'Total price': 'السعر الإجمالي',
  'Add item': 'إضافة بند',
  'Amounts do not reconcile. Check VAT, discounts, and missing items.':
      'المبالغ غير متطابقة. راجع الضريبة والخصومات والبنود المفقودة.',
  'I checked the amounts. Save the displayed invoice total.':
      'راجعت المبالغ. احفظ إجمالي الفاتورة المعروض.',
  'Saved as one expense with all items attached. Only the invoice total affects your balance and budget; tax is not added twice.':
      'تُحفظ كمصروف واحد مرفق به جميع البنود. يؤثر إجمالي الفاتورة فقط على رصيدك وميزانيتك، ولا تُضاف الضريبة مرتين.',
  'Add Expense': 'إضافة مصروف',
  'Review the amounts and confirm the invoice total before saving.':
      'راجع المبالغ وأكّد إجمالي الفاتورة قبل الحفظ.',
  'Could not save this invoice. Check the fields and try again.':
      'تعذّر حفظ الفاتورة. تحقّق من الحقول وحاول مجدداً.',
  'Enter an amount': 'أدخل مبلغاً',
  'Enter a valid non-negative number': 'أدخل رقماً صالحاً غير سالب',
  'Choose language': 'اختر اللغة',
  'of {0} · {1}%': 'من {0} · {1}٪',
  'Cumulative spending over {0} days: {1}':
      'الإنفاق التراكمي خلال {0} أيام: {1}',
  'SAMPLE': 'تجريبية',
  'Add an entry or change your filters.': 'أضف معاملة أو غيّر المرشحات.',
  'Category budgets': 'ميزانيات الفئات',
  'Tap a category to view its expenses. Tap an expense to edit it.':
      'اضغط على الفئة لعرض مصروفاتها، ثم اضغط على المصروف لتعديله.',
  'No expenses in this category this month.':
      'لا توجد مصروفات في هذه الفئة لهذا الشهر.',
  '1 expense': 'مصروف واحد',
  '{0} expenses': '{0} مصروفات',
  'Category limits sit within the overall budget; they are not added to it.':
      'حدود الفئات جزء من الميزانية الإجمالية ولا تُضاف إليها.',
  'Create a goal and record contributions as you save.':
      'أنشئ هدفاً وسجل دفعات الادخار.',
  'Delete goal?': 'حذف الهدف؟',
  'Enter a positive amount (up to 2 decimals)':
      'أدخل مبلغاً موجباً بحد أقصى منزلتين عشريتين',
  'Enter a positive amount with up to 2 decimals':
      'أدخل مبلغاً موجباً بحد أقصى منزلتين عشريتين',
  'Enter a positive target with up to 2 decimals':
      'أدخل هدفاً مالياً موجباً بحد أقصى منزلتين عشريتين',
  'Every step counts': 'كل خطوة مهمة',
  'Fresh produce          80.00': 'منتجات طازجة          80.00',
  'Give your savings a purpose': 'امنح مدخراتك هدفاً',
  'Household items      34.50': 'مستلزمات منزلية      34.50',
  'Image is too large. Choose a smaller image.':
      'الصورة كبيرة جداً. اختر صورة أصغر.',
  'Keep your plan up to date': 'حدّث خطتك باستمرار',
  'Currency is fixed after setup. You can change the app language from Profile.':
      'تثبت العملة بعد الإعداد. يمكنك تغيير لغة التطبيق من الملف الشخصي.',
  'Make room for your next chapter': 'استعد لخطوتك التالية',
  'Name your goal': 'سمِّ هدفك',
  'No transactions found': 'لا توجد معاملات مطابقة',
  'Tadbeer · 0.1\nIncome, expenses, budgets and savings goals in one place.':
      'تدبير · 0.1\nالدخل والمصروفات والميزانيات وأهداف الادخار في مكان واحد.',
  'OCR is unavailable on this platform. Enter details manually.':
      'التعرف الضوئي غير متاح على هذه المنصة. أدخل التفاصيل يدوياً.',
  'PALM MARKET': 'سوق النخيل',
  'Pantry staples          72.00': 'مواد غذائية          72.00',
  'Record a contribution when you set money aside.':
      'سجل دفعة عند تخصيص مبلغ للادخار.',
  'Record your progress': 'سجل تقدمك',
  'Remove this goal and its recorded contributions?':
      'حذف هذا الهدف ودفعاته المسجلة؟',
  'Sample receipt · Total includes VAT':
      'فاتورة تجريبية · الإجمالي شامل الضريبة',
  'Save at your own pace. Add a date for a monthly target.':
      'ادخر حسب قدرتك. أضف موعداً لحساب مبلغ شهري مستهدف.',
  'The deadline has passed. Edit your goal to set a new date.':
      'انتهى الموعد المستهدف. عدّل الهدف وحدد موعداً جديداً.',
  'This records money you have already set aside. It does not transfer money or change your expense totals.':
      'يسجل هذا المبلغ الذي ادخرته بالفعل، دون تحويل أموال أو تغيير إجمالي المصروفات.',
  'Verify extracted fields; VAT included in total.':
      'تحقق من الحقول المستخرجة؛ الإجمالي شامل الضريبة.',
  'What are you saving for?': 'لأي غرض تدخر؟',
  'You reached your goal.': 'حققت هدفك.',
  'Your deadline': 'الموعد المستهدف',
  'Your first step is waiting': 'خطوتك الأولى بانتظارك',
  'Your recorded contributions stay with this goal when you change its name, target or deadline.':
      'تبقى دفعاتك المسجلة عند تغيير اسم الهدف أو مبلغه أو موعده.',
  'Target {0}': 'الهدف {0}',
  'Illustrative monthly contribution: {0} to reach your deadline.':
      'دفعة شهرية توضيحية: {0} للوصول إلى الموعد المستهدف.',
  '{0} left to reach your goal.': 'يتبقى {0} للوصول إلى هدفك.',
  '{0} of {1}': '{0} من {1}',
  'not set': 'غير محددة',
  '{0} / not set': '{0} / غير محددة',
  'Other categories': 'فئات أخرى',
  'Saved data could not be read. It has not been overwritten. Restart or clear saved data from Profile.':
      'تعذرت قراءة البيانات المحفوظة ولم تُستبدل. أعد التشغيل أو امسح البيانات المحفوظة من الملف الشخصي.',
  'Changes could not be saved. Keep the app open and tap Retry.':
      'تعذر حفظ التغييرات. أبقِ التطبيق مفتوحاً واضغط إعادة المحاولة.',
  'Home': 'الرئيسية',
  'Expenses': 'المصروفات',
  'Analysis': 'التحليل',
  'Profile': 'الملف الشخصي',
  'TADBEER  /  MONEY MANAGEMENT': 'تدبير / إدارة أموالك',
  'Hello, {0}': 'مرحباً، {0}',
  'Make every income and expense count.': 'تابع كل دخل وكل مصروف.',
  'MONTHLY CASH FLOW': 'التدفق النقدي الشهري',
  'Add income': 'إضافة دخل',
  'Income and expenses': 'الدخل والمصروفات',
  'Your monthly budget': 'ميزانيتك الشهرية',
  'Monthly budget': 'الميزانية الشهرية',
  'Remaining budget': 'الميزانية المتبقية',
  'Over budget': 'تجاوز الميزانية',
  'No budget set for this month.': 'لم تُحدد ميزانية لهذا الشهر.',
  'Set a monthly budget in Analysis to track your spending limits.':
      'حدد ميزانية شهرية في التحليل لمتابعة حدود إنفاقك.',
  'Manage budget': 'إدارة الميزانية',
  'Notifications': 'الإشعارات',
  'Financial alerts': 'التنبيهات المالية',
  'TOTAL RECORDED BALANCE': 'إجمالي الرصيد المسجل',
  'Monthly change — · no prior comparison':
      'التغير الشهري — لا توجد بيانات للمقارنة',
  '{0}% net cash flow vs. previous month':
      '{0}٪ صافي التدفق النقدي مقارنة بالشهر السابق',
  'Income minus expenses · not a connected bank balance':
      'الدخل ناقص المصروفات · ليس رصيداً بنكياً متصلاً',
  'Monthly income': 'الدخل الشهري',
  'Monthly expenses': 'المصروفات الشهرية',
  'Scan Invoice': 'مسح فاتورة',
  'Scan invoice': 'مسح فاتورة',
  'Add expense': 'إضافة مصروف',
  'Capture a receipt, review the details, then save.':
      'صوّر الفاتورة وراجع التفاصيل ثم احفظها.',
  'Spending trends': 'اتجاه الإنفاق',
  'Selected month': 'الشهر المحدد',
  'Cumulative expenses · {0}': 'المصروفات التراكمية · {0}',
  'Day {0}': 'اليوم {0}',
  'Add expenses to see your spending trend.': 'أضف مصروفات لعرض اتجاه الإنفاق.',
  'Your month at a glance': 'ملخص الشهر',
  'Total spending': 'إجمالي الإنفاق',
  'Highest expense': 'أعلى مصروف',
  'Daily average': 'المتوسط اليومي',
  'Across {0} calendar days': 'خلال {0} أيام',
  'Net savings': 'صافي الادخار',
  '{0}% of income': '{0}٪ من الدخل',
  'No income recorded': 'لا يوجد دخل مسجل',
  'Spending by category': 'الإنفاق حسب الفئة',
  'Add an expense to see your breakdown.': 'أضف مصروفاً لعرض التوزيع.',
  'Budget distribution': 'توزيع الميزانية',
  'Your category allocations': 'مخصصات الفئات',
  'categories': 'فئات',
  'Set category budgets in Plan to see your allocation.':
      'حدد ميزانيات الفئات في التحليل لعرض التوزيع.',
  '{0} allocated across categories': '{0} موزعة على الفئات',
  'AI Financial Insights': 'رؤى مالية ذكية',
  'A little perspective. A better plan.': 'رؤية أوسع. خطة أفضل.',
  'Record expenses to reveal your spending patterns.':
      'سجل المصروفات للتعرف على نمط إنفاقك.',
  '{0} represents {1}% of your expenses. Reducing it by 10% would free up {2}.':
      'تمثل {0} نسبة {1}٪ من مصروفاتك. خفضها بنسبة ١٠٪ يوفر {2}.',
  'Spending is {0}% higher than the comparable period last month.':
      'زاد الإنفاق بنسبة {0}٪ مقارنة بالفترة نفسها من الشهر السابق.',
  'Spending is {0}% lower than the comparable period last month.':
      'انخفض الإنفاق بنسبة {0}٪ مقارنة بالفترة نفسها من الشهر السابق.',
  'Add prior-month entries to unlock a spending comparison.':
      'أضف معاملات الشهر السابق لمقارنة الإنفاق.',
  'RULE-BASED INSIGHTS': 'رؤى مبنية على قواعد حسابية',
  'Recent transactions': 'المعاملات الأخيرة',
  'View all': 'عرض الكل',
  'No transactions this month.': 'لا توجد معاملات لهذا الشهر.',
  'Set a budget in Analysis to receive spending alerts.':
      'حدد ميزانية في التحليل لتلقي تنبيهات الإنفاق.',
  'No budget alerts. Your recorded expenses are within the limits you have set.':
      'لا توجد تنبيهات. مصروفاتك المسجلة ضمن الحدود المحددة.',
  'You have used {0}% of your monthly budget. Review your remaining limits in Analysis.':
      'استخدمت {0}٪ من الميزانية الشهرية. راجع الحدود المتبقية في التحليل.',
  'Previous month': 'الشهر السابق',
  'Next month': 'الشهر التالي',
  'Settings': 'الإعدادات',
  'Retry': 'إعادة المحاولة',
  'Your money.\nA clearer direction.': 'أموالك.\nوجهة أوضح.',
  'Track your income and expenses, stay within budget, and build better money habits.':
      'تابع دخلك ومصروفاتك، والتزم بميزانيتك، وابنِ عادات مالية أفضل.',
  'What should we call you?': 'بأي اسم نناديك؟',
  'Your first name': 'اسمك الأول',
  'Your currency': 'عملتك',
  'Get started': 'ابدأ الآن',
  'Clear saved data': 'مسح البيانات المحفوظة',
  'Clear unreadable data?': 'مسح البيانات غير القابلة للقراءة؟',
  'This permanently removes the saved workspace.':
      'سيؤدي ذلك إلى حذف مساحة العمل المحفوظة نهائياً.',
  'Your profile': 'ملفك الشخصي',
  'Currency': 'العملة',
  '{0} · fixed for this workspace': '{0} · ثابتة لهذه المساحة',
  'Backend services': 'خدمات الخادم',
  'Receipt analysis and product search': 'تحليل الفواتير والبحث عن المنتجات',
  'Workspace mode': 'نوع المساحة',
  'Sample data': 'بيانات تجريبية',
  'Personal entries': 'معاملات شخصية',
  'Data processing': 'معالجة البيانات',
  'Clear saved data?': 'مسح البيانات المحفوظة؟',
  'Clear data': 'مسح البيانات',
  'Saved transactions, recurring schedules, receipt images, budgets and goals will be permanently removed.':
      'ستُحذف المعاملات وجداول التكرار وصور الفواتير والميزانيات والأهداف المحفوظة نهائياً.',
  'Receipt images and product searches are sent to the configured backend for processing. Review extracted details before saving an expense.':
      'تُرسل صور الفواتير وطلبات البحث عن المنتجات إلى الخادم المُعدّ لمعالجتها. راجع التفاصيل المستخرجة قبل حفظ المصروف.',
  'Food': 'الطعام',
  'Transportation': 'المواصلات',
  'Housing': 'السكن',
  'Utilities': 'الخدمات',
  'Shopping': 'التسوق',
  'Healthcare': 'الصحة',
  'Entertainment': 'الترفيه',
  'Education': 'التعليم',
  'Subscriptions': 'الاشتراكات',
  'Travel': 'السفر',
  'Other': 'أخرى',
  'Overall': 'الإجمالي',
  'Income': 'الدخل',
  'Expense': 'مصروف',
  'All': 'الكل',
  'All categories': 'جميع الفئات',
  'Your money trail': 'سجل أموالك',
  'YOUR MONEY TRAIL': 'سجل أموالك',
  'Transactions': 'المعاملات',
  'Add transaction': 'إضافة معاملة',
  'Search merchant or note': 'ابحث عن تاجر أو ملاحظة',
  'Category': 'الفئة',
  '{0} entries': '{0} معاملات',
  'New transaction': 'معاملة جديدة',
  'Edit transaction': 'تعديل المعاملة',
  'Review receipt': 'مراجعة الفاتورة',
  'Delete transaction': 'حذف المعاملة',
  'Delete transaction?': 'حذف المعاملة؟',
  'This removes it from your recorded totals.': 'ستُحذف من إجمالياتك المسجلة.',
  'Delete': 'حذف',
  'Source': 'المصدر',
  'Merchant': 'التاجر',
  'Enter a name': 'أدخل اسماً',
  'Amount ({0})': 'المبلغ ({0})',
  'Use a positive amount with up to 2 decimals':
      'أدخل مبلغاً موجباً بحد أقصى منزلتين عشريتين',
  'Note (optional)': 'ملاحظة (اختيارية)',
  'Saving…': 'جارٍ الحفظ…',
  'Save transaction': 'حفظ المعاملة',
  'Save changes': 'حفظ التغييرات',
  'Save expense': 'حفظ المصروف',
  'Confirm & save expense': 'تأكيد وحفظ المصروف',
  'Possible duplicate': 'تكرار محتمل',
  'An entry with this merchant, date and amount, or this receipt image, already exists. Save another?':
      'توجد معاملة بنفس التاجر والتاريخ والمبلغ أو صورة الفاتورة. هل تريد حفظ نسخة أخرى؟',
  'Save another': 'حفظ نسخة أخرى',
  'Confirm receipt': 'تأكيد الفاتورة',
  'Save {0} at {1}? The displayed total already includes any VAT.':
      'حفظ {0} لدى {1}؟ يشمل الإجمالي المعروض ضريبة القيمة المضافة.',
  'Transaction saved': 'تم حفظ المعاملة',
  'Receipt preview unavailable': 'معاينة الفاتورة غير متاحة',
  'Review every field before saving. OCR can misread totals and dates. Currency: {0}.':
      'راجع جميع الحقول قبل الحفظ؛ قد يخطئ التعرف الضوئي في الإجماليات والتواريخ. العملة: {0}.',
  'Capture. Review. Done.': 'صوّر. راجع. احفظ.',
  'CAPTURE. REVIEW. DONE.': 'صوّر. راجع. احفظ.',
  'Scan a receipt': 'مسح فاتورة',
  'Turn a receipt into an organized expense.': 'حوّل الفاتورة إلى مصروف منظم.',
  'Illustrative receipt': 'فاتورة توضيحية',
  'TOTAL · VAT INCLUDED': 'الإجمالي · شامل الضريبة',
  'You review before anything is saved': 'تراجع التفاصيل قبل حفظ أي بيانات',
  'Reading your receipt…': 'جارٍ قراءة الفاتورة…',
  'Take a photo': 'التقاط صورة',
  'Choose receipt image': 'اختيار صورة فاتورة',
  'Enter expense manually': 'إدخال مصروف يدوياً',
  'Could not read the receipt. Check camera/photo permissions, try a clearer image, or enter the expense manually.':
      'تعذرت قراءة الفاتورة. تحقق من أذونات الكاميرا والصور أو استخدم صورة أوضح أو أدخل المصروف يدوياً.',
  'Small steps. Real progress.': 'خطوات صغيرة. تقدم حقيقي.',
  'SMALL STEPS. REAL PROGRESS.': 'خطوات صغيرة. تقدم حقيقي.',
  'Analysis & planning': 'التحليل والتخطيط',
  'Budgets': 'الميزانيات',
  'Goals': 'الأهداف',
  'No overall budget set': 'لم تُحدد ميزانية إجمالية',
  '{0} BUDGET': 'ميزانية {0}',
  'of {0} · {1} remaining': 'من {0} · المتبقي {1}',
  'Edit monthly budget →': 'تعديل الميزانية الشهرية',
  'You have reached your monthly budget.': 'وصلت إلى حد الميزانية الشهرية.',
  'You have used {0}% of your monthly budget.':
      'استخدمت {0}٪ من الميزانية الشهرية.',
  'Use previous month’s budgets': 'استخدام ميزانيات الشهر السابق',
  'No missing budgets to copy from the previous month.':
      'لا توجد ميزانيات ناقصة لنسخها من الشهر السابق.',
  'Copied {0} budgets. Existing limits kept.':
      'تم نسخ {0} ميزانيات مع إبقاء الحدود الحالية.',
  '{0} budget': 'ميزانية {0}',
  'Edit {0} budget': 'تعديل ميزانية {0}',
  'Not set': 'غير محددة',
  'Set budget': 'تحديد الميزانية',
  'Remove budget': 'إزالة الميزانية',
  'Cancel': 'إلغاء',
  'Save': 'حفظ',
  'Confirm': 'تأكيد',
  'Create a goal': 'إنشاء هدف',
  'Edit goal': 'تعديل الهدف',
  'Delete goal': 'حذف الهدف',
  'Goal name': 'اسم الهدف',
  'Target ({0})': 'المبلغ المستهدف ({0})',
  'Enter a goal name': 'أدخل اسم الهدف',
  'Deadline (optional)': 'الموعد المستهدف (اختياري)',
  'No deadline': 'بدون موعد',
  'Set a date': 'تحديد موعد',
  'Change date': 'تغيير الموعد',
  'Remove deadline': 'إزالة الموعد',
  'Create goal': 'إنشاء الهدف',
  'Save goal': 'حفظ الهدف',
  'Goal removed': 'تم حذف الهدف',
  'SAVED SO FAR': 'المدخر حتى الآن',
  'Target date: {0}': 'الموعد المستهدف: {0}',
  'Record contribution': 'تسجيل دفعة ادخار',
  'Contribution history': 'سجل دفعات الادخار',
  'Contribution actions': 'إجراءات الدفعة',
  'Edit contribution': 'تعديل الدفعة',
  'Remove contribution': 'إزالة الدفعة',
  'Remove contribution?': 'إزالة الدفعة؟',
  'This corrects your recorded goal progress.':
      'سيُصحح ذلك تقدمك المسجل نحو الهدف.',
  'Save contribution': 'حفظ الدفعة',
  'Goal contributions never create expenses or change cash flow.':
      'دفعات الادخار لا تنشئ مصروفات ولا تغير التدفق النقدي.',
  'Contributions are records of your savings. This app does not move money.':
      'الدفعات سجلات لمدخراتك. لا ينقل التطبيق الأموال.',
  'Language': 'اللغة',
  'Automatic · device language': 'تلقائياً · لغة الجهاز',
  'Repeat': 'التكرار',
  'One time': 'مرة واحدة',
  'Daily': 'يومياً',
  'Weekly': 'أسبوعياً',
  'Monthly': 'شهرياً',
  'Adds an entry every day. Missed entries are added when you next open the app.':
      'تُضاف معاملة كل يوم. تُضاف المعاملات المستحقة عند فتح التطبيق مجدداً.',
  'Adds an entry every 7 days. Missed entries are added when you next open the app.':
      'تُضاف معاملة كل ٧ أيام. تُضاف المعاملات المستحقة عند فتح التطبيق مجدداً.',
  'Adds an entry on the same date each month, or the last day of a shorter month. Missed entries are added when you next open the app.':
      'تُضاف معاملة في اليوم نفسه من كل شهر، أو في آخر يوم إن كان الشهر أقصر. تُضاف المعاملات المستحقة عند فتح التطبيق مجدداً.',
  'Start date': 'تاريخ البدء',
  'Recurring': 'متكررة',
  'Recurring transactions': 'المعاملات المتكررة',
  'Manage automatic income and expenses.': 'إدارة الدخل والمصروفات التلقائية.',
  'No recurring transactions': 'لا توجد معاملات متكررة',
  'Choose a repeat schedule when adding income or an expense.':
      'اختر جدول تكرار عند إضافة دخل أو مصروف.',
  'Next entry': 'المعاملة التالية',
  'Stop repeating': 'إيقاف التكرار',
  'Stop repeating?': 'إيقاف التكرار؟',
  'Future entries will stop. Recorded transactions will stay in your history.':
      'ستتوقف المعاملات القادمة، وتبقى المعاملات المسجلة في سجلك.',
  'Repeating stopped': 'تم إيقاف التكرار',
  'Recurring transaction saved': 'تم حفظ المعاملة المتكررة',
  'Transaction could not be saved. Try again.':
      'تعذر حفظ المعاملة. حاول مجدداً.',
  'Saved data could not be cleared. Try clearing it again.':
      'تعذر مسح البيانات المحفوظة. حاول مسحها مرة أخرى.',
  'This is one recorded entry. Changes here do not change its repeat schedule.':
      'هذه معاملة مسجلة واحدة. لا تؤثر التغييرات هنا في جدول تكرارها.',
};
