# 3EQTO — Quality R1

**Development candidate: v1.9.28 / build 50** · iPhone and iPad · iOS 17+

RoomPlan scanning, editable 2D/3D surveys, electrical placement, wall photographs,
architectural correction sessions, quantity takeoff, and PDF/DXF/GLB/PNG/XLSX exports.

## هذا التحديث

تحسينات للحصر، العرض، الواجهات، التصوير والأداء الحراري، مبنية على
`373a30be1e37a7995418be1db66c1f877568d801` (v1.9.27 / Build 49.1).

- اسم العرض أصبح **3EQTO** مع الحفاظ على Bundle ID والتخزين والروابط القديمة.
- حفظ مضلعات الأرضيات الجديدة وحساب مساحتها الفعلية، مع تقدير مستطيل واضح للمسحات القديمة.
- ربط الفتحات بالحوائط، قصها عند الحدود، وعدم خصم مناطق التداخل مرتين.
- بحث وترتيب للمشروعات، معلومات أثناء المسح، وتنبيهات جودة في التطبيق والتقارير.
- إصلاح تحديث عناصر 3D دون تغير العدد، والمحافظة على الكاميرا عند تبديل الطبقات.
- ميزانية عرض تتكيف مع حالة الحرارة وتوفير الطاقة، مع تقليل تحديثات AR غير الضرورية.
- فحوصات Swift فعلية للحسابات، بالإضافة إلى فحوصات التوافق والتصدير.

**ليست نسخة معتمدة على جهاز بعد.** فحص Swift المحلي لا يغني عن Xcode، أو اختبار
المسح على iPhone. لا توجد نسبة تحسن أداء أو حرارة مقاسة لهذا التحديث حتى الآن.

التفاصيل والحدود والاختبارات: [تقرير المراجعة](Docs/3EQTO-Quality-R1-Review.md).

## البناء

الـWorkflow الحالي `build-unsigned-ipa.yml` يعمل تلقائيًا بعد Push إلى `main`.
من PowerShell، بعد Commit وPush:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Tools\Build-3EQTO.ps1
```

ولبدء تشغيل يدوي جديد:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Tools\Build-3EQTO.ps1 -Dispatch
```

يتطلب GitHub CLI (`gh auth login`). السكربت يتابع Commit المطابق، ينزّل التشخيصات،
ويتحقق من SHA256 للملف. الناتج **3EQTO-unsigned.ipa** يحتاج توقيعًا صالحًا قبل
تثبيته، مثل مسار Sideloadly المستخدم سابقًا. لا تشارك بيانات Apple ID داخل المستودع.

## هوية التوافق — لا تغيّرها لتغيير الاسم الظاهر

| البند | القيمة المحفوظة |
|---|---|
| Bundle ID | `com.essam.3E.roomelectrical` |
| Widget Bundle ID | `com.essam.3E.roomelectrical.widget` |
| Xcode project / scheme | `RoomSurveyElectrical` |
| Internal product | `3ERoomElectrical.app` |
| Shared folder | `Apps/RoomElectrical` |
| Registry key | `roomElectrical` |
| Deep links | `electrical://` + `3eroomelectrical://` |
| Project package | `.3eroom` / existing UTType |

المقصود بـbuild 50 هنا رقم حزمة iOS الجديد، وليس إنجاز محرر محاذاة المسحات
المسمى Build 50 في خارطة الطريق القديمة؛ هذا المحرر لم يُنفّذ ضمن Quality R1.
