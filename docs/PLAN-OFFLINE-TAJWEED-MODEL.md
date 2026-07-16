# خطة: بناء نموذج تجويد Offline (تقطير + تكميم + sherpa-onnx)

> **الهدف**: تحويل نموذج quran-muaalem (660M، 2.4GB) إلى نموذج صغير (<100MB) يعمل على الجهاز بِدون خادم، مع الحفاظ على قدرة كشف أخطاء التجويد.
>
> **الحالة**: وثيقة تخطيط — لم يُبدأ التنفيذ بعد.

---

## 📋 جدول المحتويات

1. [نظرة عامة](#1-نظرة-عامة)
2. [البنية المعمارية الهدف](#2-البنية-المعمارية-الهدف)
3. [البيانات والتوسيم](#3-البيانات-والتوسيم)
4. [تقطير النموذج (Distillation)](#4-تقطير-النموذج-distillation)
5. [تصدير ONNX والتكميم (Quantization)](#5-تصدير-onnx-والتكميم-quantization)
6. [تكامل sherpa-onnx في Flutter](#6-تكامل-sherpa-onnx-في-flutter)
7. [التقييم والتحقّق](#7-التقييم-والتحقّق)
8. [الموارد المطلوبة](#8-الموارد-المطلوبة)
9. [الجدول الزمني](#9-الجدول-الزمني)
10. [المراجع](#10-المراجع)
11. [القرارات الحرجة](#11-القرارات-الحرجة)
12. [المخاطر والعوائق](#12-المخاطر-والعوائق)

---

## 1. نظرة عامة

### المشكلة

نموذج [`obadx/muaalem-model-v3_2`](https://huggingface.co/obadx/muaalem-model-v3_2) ممتاز في كشف أخطاء التجويد لكنّه:
- حجم ضخم: **2.4GB** (Wav2Vec2-BERT 2.0، 660M معامل)
- يتطلب خادم Python بِـ GPU أو CPU قوي
- لا يعمل على الجهاز مباشرةً
- زمن استجابة 5-15s على CPU

### الهدف

نموذج تجويد **Offline** بِالمواصفات التالية:

| المعيار | الهدف | الكيفية |
|---------|-------|---------|
| **الحجم** | <100MB (int8 ONNX) | تقطير إلى wav2vec2-base (95M) + تكميم int8 |
| **السرعة** | زمن حقيقي على الهاتف | sherpa-onnx + int8 على CPU |
| **التجويد** | كشف الصفات (التفخيم، الإخفاء، القلقلة...) | 11 رأس CTC (فونيمات + 10 صفات) |
| **Deployment** | On-device Flutter/Dart | sherpa_onnx Dart package |
| **الرخصة** | MIT | بيانات تجارية (OpenSLR MIT + AQQD CC BY) |

### لماذا هذا ممكن تقنياً؟

النموذج الكبير (660M) يستخدم Wav2Vec2-BERT كَـ backbone ضخم، لكن **المهمّة نفسها** (تصنيف 43 فونيم + 10 صفات) يمكن لنموذج أصغر بِكثير تعلّمها عبر **تقطير المعرفة** (Knowledge Distillation): المعلّم (الكبير) يُولّد soft labels، والطالب (الصغير) يتعلّم منها + labels الصلبة.

**سابقة مثبتة**: مشروع [`ReciteQuran`](https://github.com/Iam-Muslim/ReciteQuran) يستخدم نموذج Zipformer CTC int8 بحجم **69MB** فقط ويعمل offline على الهاتف — لكنّه يكشف المدود فقط (لا الصفات). خطّتنا تضيف الصفات عبر تقطير الرؤوس الكاملة من quran-muaalem.

---

## 2. البنية المعمارية الهدف

### المعلّم (Teacher) — موجود

```
obadx/muaalem-model-v3_2
├── النوع: Wav2Vec2BertForMultilevelCTC (مخصّص)
├── المعاملات: 660M (2.4GB float32)
├── Encoder: 24 طبقة، hidden=1024، 16 heads، Conformer kernel=31
├── 11 رأس CTC:
│   ├── phonemes (vocab=43، weight=0.40)
│   ├── hams_or_jahr (vocab=3)
│   ├── shidda_or_rakhawa (vocab=4)
│   ├── tafkheem_or_taqeeq (vocab=4)
│   ├── itbaq (vocab=3)
│   ├── safeer (vocab=3)
│   ├── qalqla (vocab=3)
│   ├── tikraar (vocab=3)
│   ├── tafashie (vocab=3)
│   ├── istitala (vocab=3)
│   └── ghonna (vocab=3)
└── الرخصة: MIT
```

- 🔗 [config.json](https://huggingface.co/obadx/muaalem-model-v3_2/raw/main/config.json)
- 🔗 [النموذج على HuggingFace](https://huggingface.co/obadx/muaalem-model-v3_2)
- 🔗 [الورقة العلمية (arXiv:2509.00094)](https://arxiv.org/abs/2509.00094)

### الطالب (Student) — سيتمّ بناؤه

```
student-model (جديد)
├── النوع: wav2vec2-base encoder + 11 رأس CTC (نفس المعلّم)
├── المعاملات: ~95-100M (هدف <100MB int8)
├── Encoder: 12 طبقة، hidden=768، 8 heads (نصف المعلّم)
├── 11 رأس CTC (نفس المعلّم تماماً):
│   └── ... نفس الرؤوس والأوزان (level_to_vocab_size + level_to_loss_weight)
├── التهيئة: من wav2vec2-base مُدرَّب مُسبقاً (إن وُجد قرآني) أو من الصفر
└── التدريب: Knowledge Distillation من المعلّم
```

### لماذا wav2vec2-base؟

- **95M معامل** (1/7 من المعلّم) → int8 ≈ **~95MB**
- 12 طبقة بدل 24 (نصف العمق)
- hidden=768 بدل 1024 (75% السعة)
- معروف ومُجرَّب للتعرّف الصوتي على الهاتف
- معتمد في sherpa-onnx عبر ONNX Runtime

---

## 3. البيانات والتوسيم

### مصادر البيانات (تجارية OK)

| المصدر | الحجم | الرخصة | الاستخدام |
|--------|-------|--------|-----------|
| [**OpenSLR #132**](https://www.openslr.org/132/) | ~30 ساعة | **MIT** ✅ | تدريب أساسي |
| [**AQQD v1.0**](https://www.researchsquare.com/article/rs-8804884/latest.pdf) | متنوّع | **CC BY 4.0** ✅ | تدريب إضافي |
| [**FaisaI/tadabur**](https://huggingface.co/datasets/FaisaI/tadabur) | **1400 ساعة** | CC BY-NC 4.0 ⚠️ | **تقييم فقط** (لا تدريب تجاري) |

> ⚠️ **تنبيه**: tadabur رخصتها CC BY-NC (غير تجاري). يمكن استخدامها لِـ **البحث والتقييم** فقط، لا لِتدريب نموذج تجاري. النموذج الناتج لِلاستخدام التجاري يجب أن يُدرَّب على OpenSLR + AQQD فقط.

### خطّ أنابيب التوسيم (Labeling Pipeline)

استخدم [**`quran-transcript`**](https://github.com/obadx/quran-transcript) (نفس مؤلّف quran-muaalem) لِتوليد Labels تلقائياً:

```python
from quran_transcript import quran_phonetizer

# من النص العثماني → 11 مجموعة Labels مطابقة لِرؤوس المعلّم
result = quran_phonetizer(
    uthmani_script="بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ",
    moshaf_attributes=MoshafAttributes(rewaya="hafs", madd_monfasel_len=4, ...)
)
# result.phonemes → "بِسْمِ ٱللَّهِ ..." (43 رمز QPS)
# result.sifat → صفات لِكل حرف (10 فئات)
# result.mappings → ربط الحرف بِالصوت
```

**مزايا `quran-transcript`:**
- الـ 43 فونيم + 10 صفات **تطابق رؤوس المعلّم تماماً**
- يدعم ~30 إعداد مصحف (Hafs، Warsh، Qalon...)
- يُولّد Labels لِكل ساعة صوت بِثوانٍ
- يُوفّر `explain_error()` لِتقييم النتيجة لاحقاً

### خطوات التوسيم

```
1. صوت قرآني (WAV 16kHz)
2. نص عثماني مرجعي (من Tanzil)
3. Forced alignment (torchaudio) → timestamps لِكل كلمة
4. quran_phonetizer → 11 مجموعة Labels إطاراً بِإطار
5. Labels جاهزة لِلتدريب
```

- 🔗 [quran-transcript على PyPI](https://pypi.org/project/quran-transcript/)
- 🔗 [quran-transcript GitHub](https://github.com/obadx/quran-transcript)
- 🔗 [Tanzil Quran text](https://tanzil.net/download/)

---

## 4. تقطير النموذج (Distillation)

### الاستراتيجية

**Knowledge Distillation** بِنمط HuggingFace القياسي — يجمع بين:
- **CTC task loss** على hard labels (الفونيمات + الصفات المرجعية)
- **KL-divergence loss** بين logits المعلّم والطالب (soft labels)

### كود DistillationTrainer

```python
import torch
import torch.nn.functional as F
from transformers import Trainer

class TajweedDistillationTrainer(Trainer):
    """تقطير المعرفة من Wav2Vec2-BERT (معلّم) إلى wav2vec2-base (طالب)
    مع 11 رأس CTC (فونيمات + 10 صفات)."""

    def __init__(self, *args, teacher=None, alpha=0.5, T=2.0,
                 head_weights=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.teacher = teacher.eval()  # المعلّم ثابت (لا تدريب)
        self.alpha = alpha              # وزن task loss vs KD loss
        self.T = T                      # درجة الحرارة (Temperature)
        # أوزان الرؤوس من config المعلّم (0.40 لِلفونيمات، 0.06 لِكل صفة)
        self.head_weights = head_weights or [0.40] + [0.06] * 10

    def compute_loss(self, model, inputs, return_outputs=False):
        # 1) المعلّم: Forward واحد بِدون gradient
        with torch.no_grad():
            teacher_outputs = self.teacher(**inputs)
            teacher_logits = teacher_outputs.logits  # list of 11 tensors

        # 2) الطالب: Forward
        student_outputs = model(**inputs)
        student_logits = student_outputs.logits  # list of 11 tensors

        # 3) Loss = α × (task CTC loss) + (1-α) × (KL distillation)
        loss = 0
        for i in range(11):
            # CTC task loss (hard labels)
            ctc_loss = self.ctc_losses[i](
                student_logits[i].transpose(0, 1),
                inputs[f"labels_{i}"],
                inputs["audio_lengths"],
                inputs[f"label_lengths_{i}"],
            )
            # KL divergence (soft labels من المعلّم)
            kl_loss = F.kl_div(
                F.log_softmax(student_logits[i] / self.T, dim=-1),
                F.softmax(teacher_logits[i] / self.T, dim=-1),
                reduction='batchmean',
            ) * (self.T ** 2)
            loss += self.head_weights[i] * (
                self.alpha * ctc_loss + (1 - self.alpha) * kl_loss
            )

        return (loss, student_outputs) if return_outputs else loss
```

### المعاملات (Hyperparameters)

| المعامل | القيمة | السبب |
|---------|--------|-------|
| **T (Temperature)** | 2-4 | قيمة قياسية لِـ KD |
| **α (task weight)** | 0.5 | توازن بين hard/soft labels |
| **batch size** | 16 | متطلّب ذاكرة A100 80GB |
| **learning rate** | 1e-4 | Adam optimizer |
| **epochs** | 10-30 | حسب التقارب |
| **weights[0]** | 0.40 (phonemes) | من config المعلّم |
| **weights[1-10]** | 0.06 لِكل صفة | من config المعلّم |

### التهيئة (Initialization)

ابحث عن wav2vec2-base مُدرَّب على العربية/القرآن:
- [`tarteel-ai/whisper-base-ar-quran`](https://huggingface.co/tarteel-ai/whisper-base-ar-quran) — Whisper لكن قد يصلح
- أو **`facebook/wav2vec2-base`** العام ثم fine-tune

إن لم تجد wav2vec2-base قرآني، استخدم wav2vec2-base العام واضبطه على بيانات القرآن قبل التقطير.

### المراجع التقنية لِلتقطير

- [**Phil Schmid — KD for BERT with Transformers**](https://www.philschmid.de/knowledge-distillation-bert-transformers) — النمط القياسي لِـ DistillationTrainer
- [**HF Docs — Knowledge Distillation**](https://huggingface.co/docs/transformers/en/tasks/knowledge_distillation_for_image_classification) — دليل رسمي
- [**AdaKD (arXiv 2405.08019)**](https://arxiv.org/html/2405.08019v1) — KD لِـ wav2vec2 على A100 80GB
- [**Kerpicci et al. INTERSPEECH 2023**](https://www.isca-archive.org/interspeech_2023/kerpicci23_interspeech.pdf) — KD لِـ multi-task wav2vec2

---

## 5. تصدير ONNX والتكميم (Quantization)

### ⚠️ تحدٍّ معروف: `multi_level_ctc` غير مدعوم بِـ `optimum-cli`

النموذج الأصلي يستخدم `Wav2Vec2BertForMultilevelCTC` (مخصّص) بِـ 11 مخرج. `optimum-cli export` **لا يتعرف عليه** ([Issue #2082](https://github.com/huggingface/optimum/issues/2082)). لذا نحتاج **تصدير يدوي**:

```python
import torch

# صدّر 11 مخرج في graph واحد
torch.onnx.export(
    student_model,
    (audio_input, attention_mask),
    "muaalem_student.onnx",
    input_names=["audio", "attention_mask"],
    output_names=[f"logits_{i}" for i in range(11)],  # 11 رأس
    dynamic_axes={
        "audio": {0: "batch", 1: "time"},
        "attention_mask": {0: "batch", 1: "time"},
    },
    opset_version=17,
)
```

- 🔗 [optimum #2082: wav2vec2-bert ONNX export](https://github.com/huggingface/optimum/issues/2082)
- 🔗 [Yehor/w2v-bert-uk-v2.1-onnx-gpu](https://huggingface.co/Yehor/w2v-bert-uk-v2.1-onnx-gpu) — سابقة w2v-bert → ONNX

### التكميم int8

استخدم **dynamic quantization** (ليس static) لِتفادي bug معروف في attention subgraphs:

```python
from onnxruntime.quantization import quantize_dynamic, QuantType

quantize_dynamic(
    "muaalem_student.onnx",
    "muaalem_student.int8.onnx",
    weight_type=QuantType.QInt8,  # dynamic — لا يحتاج calibration data
)
```

**لماذا dynamic وليس static؟**
- Static quantization يفشل على multi-head attention ([onnxruntime#17278](https://github.com/microsoft/onnxruntime/issues/17278))
- Dynamic أبسط (لا يحتاج calibration) ونتائجه قريبة
- خسارة الدقّة المتوقَّعة: <1-3% WER على الصوت النظيف

- 🔗 [ONNX Runtime Quantization docs](https://onnxruntime.ai/docs/performance/model-optimizations/quantization.html)
- 🔗 [SpeechBrain quantization tutorial](https://speechbrain.readthedocs.io/en/stable/tutorials/advanced/model-quantization.html)

### النتيجة المتوقَّعة

```
الطالب (float32): ~380MB  (95M × 4 bytes)
بَعد int8:         ~95MB  (95M × 1 byte)  ← الهدف ✅
```

---

## 6. تكامل sherpa-onnx في Flutter

### ⚠️ تحدٍّ معروف: sherpa-onnx يدعم CTC **أحادي الرأس** فقط

sherpa-onnx يفترض **مخرج CTC واحد** لِكل ملف ONNX. النموذج بِـ 11 رأس يحتاج معالجة خاصة.

### الخيار أ: تقسيم الرؤوس (مُوصى به لِتغطية كاملة)

صدّر النموذج كَـ **ملفّين منفصلين**:

```python
# 1) phonemes فقط (لِـ sherpa-onnx الافتراضي)
torch.onnx.export(student_phonemes_only, ..., "phonemes.onnx")
# 2) sifat كاملة (لِـ ONNX Runtime مباشرة)
torch.onnx.export(student_sifat_only, ..., "sifat.onnx")
```

في Flutter:

```dart
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// 1) sherpa-onnx: تعرّف الفونيمات + alignment
final config = sherpa.OfflineRecognizerConfig(
  modelConfig: sherpa.OfflineModelConfig(
    nemoCtc: sherpa.OfflineNemoCtcModelConfig(
      model: 'assets/models/phonemes.int8.onnx',
    ),
    tokens: 'assets/models/tokens.txt',
    numThreads: 2,
    debug: false,
    modelType: 'nemo_ctc',
  ),
);
final recognizer = sherpa.OfflineRecognizer(config);
final stream = recognizer.createStream();
stream.acceptWaveform(samples, 16000);  // Float list
recognizer.decode(stream);
final predictedPhonemes = recognizer.getResult(stream).text;

// 2) ONNX Runtime مباشرة: صفات الحروف
// (تحتاج package:onnxruntime أو FFI منفصل)
// شغّل sifat.int8.onnx واحصل على 10 مخرجات صفات
```

### الخيار ب: نموذج phonemes-only لِلموبايل (أبسط)

صدّر **رأس الفونيمات فقط** لِلموبايل (دون الصفات). هذا يُعطي:
- ✅ محاذاة كلمات (correct/skipped)
- ✅ كشف المدود (من طول الفونيمات المتكرّرة — حيلة ReciteQuran)
- ❌ لا صفات (التفخيم/الإخفاء/القلقلة) → تبقى على الخادم

هذا أبسط خيار ويعطي **~70% من قيمة quran-muaalem** بِدون أي خادم.

### بنية ملفات sherpa-onnx

```
assets/models/
├── phonemes.int8.onnx     # رأس الفونيمات (sherpa-onnx)
├── tokens.txt             # 43 رمز فونيم (سطر لِكل رمز، CTC blank = سطر 0)
└── sifat.int8.onnx        # رؤوس الصفات (ONNX Runtime، اختياري)
```

### مراجع sherpa-onnx

- [sherpa-onnx GitHub](https://github.com/k2-fsa/sherpa-onnx)
- [sherpa_onnx Dart package](https://pub.dev/packages/sherpa_onnx)
- [NeMo → sherpa-onnx export guide](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-ctc/nemo/how-to-export.html)
- [ReciteQuran sherpa_engine.dart](https://github.com/Iam-Muslim/ReciteQuran/blob/main/lib/engine/sherpa_engine.dart) — سابقة مباشرة لِـ Flutter + sherpa-onnx Quran ASR

---

## 7. التقييم والتحقّق

### مقاييس التقييم

| المقياس | الأداة | الهدف |
|---------|-------|-------|
| **PER (Phoneme Error Rate)** | `jiwer` | <10% (مقارنة بِـ ~6% لِلأصل) |
| **Tajweed Detection F1** | `quran-transcript.explain_error` | مقارنة قبل/بَعد التكميم |
| **الزمن** | Stopwatch على هاتف حقيقي | <2s لِكل آية |
| **الذاكرة** | Flutter DevTools profiler | <200MB RAM وقت الاستدلال |
| **حجم الملف** | `ls -la` | <100MB |

### منهجية التقييم

```python
from quran_transcript import explain_error

# 1) شغّل المعلّم (2.4GB) على مجموعة اختبار → reference errors
# 2) شغّل الطالب (95MB) على نفس المجموعة → student errors
# 3) قارن بِـ explain_error:
for audio in test_set:
    teacher_errors = run_teacher(audio)
    student_errors = run_student(audio)
    # مدى التطابق في:
    #   - عدد الأخطاء المُكتشَفة
    #   - نوع الخطأ (tajweed/normal/tashkeel)
    #   - موضع الخطأ
    #   - اسم القاعدة
```

### مجموعة الاختبار

استخدم **tadabur** (CC BY-NC، تقييم فقط OK):
- 100 مقطع متنوّع (قرّاؤن مختلفون، سرعات مختلفة)
- موسومة بِـ `quran-transcript`
- قارن: أصل → طالب → طالب int8

---

## 8. الموارد المطلوبة

### الأجهزة

| المرحلة | الجهاز | المدة | التكلفة التقديرية |
|---------|--------|------|-------------------|
| **توليد soft labels (معلّم)** | A100 80GB | 1-2 يوم | ~$30-60 (RunPod) |
| **تقطير الطالب** | A100 80GB | 2-5 أيام | ~$60-150 |
| **تصدير + تكميم** | أي GPU (T4 يكفي) | 1 يوم | ~$5-10 |
| **اختبار وتكامل** | Mac + هاتف | 3-5 أيام | مجاناً |

**الإجمالي**: ~$95-220 + ~2-3 أسابيع عمل

> 💡 **ملاحظة**: استئجار A100 80GB من [RunPod](https://runpod.io) ~$1.10/ساعة. لتقليل التكلفة: استخدم 4-8× A100 لِيوم واحد بدل A100 واحد لِـ 5 أيام. راجع [مقارنة H100 vs A100](https://lyceum.technology/magazine/h100-80gb-vs-a100-80gb-fine-tuning/).

### البرمجيات

```bash
pip install torch transformers optimum[onnx] onnxruntime
pip install quran-muaalem quran-transcript librosa
pip install sherpa-onnx  # لِلاختبار على desktop
pip install jiwer        # لِحساب PER
```

### المهارات المطلوبة

- ✅ **Python ML** (PyTorch، HuggingFace transformers)
- ✅ **ONNX export/quantization**
- ✅ **Flutter/Dart** (sherpa_onnx integration)
- ⚠️ **فهم تجويد القرآن** (لِتقييم جودة النتائج)

---

## 9. الجدول الزمني

| المرحلة | المدة | التفاصيل |
|---------|------|-----------|
| **1. إعداد البيانات** | 2-4 أيام | تنزيل OpenSLR + AQQD، توليد Labels بِـ `quran-transcript`، forced alignment |
| **2. توليد soft labels** | 1-2 يوم (GPU) | تشغيل المعلّم على كل البيانات، حفظ logits |
| **3. تقطير الطالب** | 2-5 أيام (GPU) | تدريب wav2vec2-base (95M) من soft + hard labels |
| **4. تصدير ONNX** | 1-2 يوم | `torch.onnx.export` يدوي (11 مخرج)، تصحيح أخطاء |
| **5. تكميم int8** | 1 يوم | `quantize_dynamic`، تقييم خسارة الدقّة |
| **6. تكامل sherpa-onnx** | 3-5 أيام | Flutter wiring، OfflineRecognizer، sifat post-processing |
| **7. تقييم وضبط** | 2-3 أيام | مقارنة بِالمعلّم، قياس الأداء على هاتف |
| **الإجمالي** | **~2-3 أسابيع** | (مع 6-12 A100-day من GPU) |

> على 4-8× A100s، تتقلّص مرحلة التقطير إلى <1 يوم → الإجمالي **~1 أسبوع**.

---

## 10. المراجع

### النماذج والبيانات
- **المعلّم**: [obadx/muaalem-model-v3_2](https://huggingface.co/obadx/muaalem-model-v3_2) (660M، MIT)
- **quran-transcript**: [PyPI](https://pypi.org/project/quran-transcript/) | [GitHub](https://github.com/obadx/quran-transcript)
- **OpenSLR #132** (MIT): [openslr.org/132](https://www.openslr.org/132/)
- **AQQD** (CC BY 4.0): [Research Square](https://www.researchsquare.com/article/rs-8804884/latest.pdf)
- **tadabur** (CC BY-NC، تقييم فقط): [HuggingFace](https://huggingface.co/datasets/FaisaI/tadabur)
- **الورقة العلمية**: [arXiv:2509.00094](https://arxiv.org/abs/2509.00094)

### الأدوات
- **sherpa-onnx**: [GitHub](https://github.com/k2-fsa/sherpa-onnx) | [Dart package](https://pub.dev/packages/sherpa_onnx)
- **HuggingFace optimum**: [ONNX export docs](https://huggingface.co/docs/optimum-onnx/onnx/usage_guides/export_a_model)
- **ONNX Runtime quantization**: [docs](https://onnxruntime.ai/docs/performance/model-optimizations/quantization.html)

### سابقة (ReciteQuran)
- **GitHub**: [Iam-Muslim/ReciteQuran](https://github.com/Iam-Muslim/ReciteQuran)
- **sherpa_engine.dart**: [المصدر](https://github.com/Iam-Muslim/ReciteQuran/blob/main/lib/engine/sherpa_engine.dart)
- نموذج: Zipformer CTC int8، **69MB**، offline على الهاتف

### أوراق علمية (Knowledge Distillation)
- **Phil Schmid KD**: [philschmid.de](https://www.philschmid.de/knowledge-distillation-bert-transformers)
- **HF KD guide**: [HF docs](https://huggingface.co/docs/transformers/en/tasks/knowledge_distillation_for_image_classification)
- **AdaKD**: [arXiv:2405.08019](https://arxiv.org/html/2405.08019v1)
- **Kerpicci multi-task KD**: [INTERSPEECH 2023](https://www.isca-archive.org/interspeech_2023/kerpicci23_interspeech.pdf)
- **SSL quantization impact**: [arXiv:2309.14462](https://arxiv.org/pdf/2309.14462)

### تحديات معروفة (GitHub Issues)
- **optimum #2082**: [wav2vec2-bert ONNX export](https://github.com/huggingface/optimum/issues/2082)
- **onnxruntime #17278**: [static quantization + attention bug](https://github.com/microsoft/onnxruntime/issues/17278)
- **sherpa-onnx #569**: [multi-model packaging](https://github.com/k2-fsa/sherpa-onnx/issues/569)

### تكامل Flutter
- **quran_audio** (المكتبة الهدف): [GitHub](https://github.com/alheekmahlib/quran_audio)
- **نماذج sherpa-onnx int8 جاهزة** (مرجعية): [csukuangfj models](https://huggingface.co/csukuangfj/sherpa-onnx-moonshine-tiny-en-int8)

---

## 11. القرارات الحرجة

| القرار | الخيار المُختار | البديل |
|--------|-----------------|--------|
| **الطالب** | wav2vec2-base (95M، 12 طبقة) | Wav2Vec2-BERT صغير (معقّد) |
| **التقطير** | logit-level KD (KL divergence) | sequence-level (pseudo-labels) |
| **التكميم** | dynamic int8 (`quantize_dynamic`) | static int8 (bug مع attention) |
| **sherpa-onnx** | رأس phonemes + ONNX Runtime لِـ sifat | نموذج 11-رأس واحد (غير مدعوم) |
| **البيانات** | OpenSLR + AQQD (تجاري OK) | tadabur (CC BY-NC، تقييم فقط) |
| **GPU** | A100 80GB (أو 4-8× A100) | V100 32GB (بطيء، محدود الذاكرة) |

---

## 12. المخاطر والعوائق

| الخطر | الاحتمال | التأثير | التخفيف |
|-------|---------|--------|---------|
| **خسارة دقّة كبيرة بَعد التقطير** | متوسط | عالي | استخدم logit-level KD (ليس sequence-level)، اضبط T و α |
| **int8 يُضرّ صفات الحروف** | متوسط | متوسط | استخدم mixed precision (conv → int8، attention → fp16) |
| **sherpa-onnx لا يقبل 11 رأس** | مؤكّد | عالي | تقسيم: phonemes لِـ sherpa + sifat لِـ ONNX Runtime |
| **بيانات تدريب غير كافية** | متوسط | متوسط | استخدم tadabur لِـ pseudo-labels (بحث فقط) + اجمع بياناتك |
| **OOM أثناء التقطير** | منخفض | عالي | A100 80GB يكفي، gradient checkpointing، batch 16 |
| **قيد رخصة ReciteQuran** | لا ينطبق | — | لا ننسخ كود ReciteQuran — نبني من الصفر بِرخصة MIT |

---

> **ملاحظة أخيرة**: هذه الخطة قابلة لِلتنفيذ بِكاملها بِالأدوات الحالية. أكبر عائق هو **وقت GPU** (~$100-200) و**جودة البيانات** (OpenSLR + AQQD قد لا تكفي لِكامل الدقّة — قد تحتاج جمع بيانات إضافية).
>
> **استراتيجية تقدّّم تدريجي**: ابدأ بِالنموذج phonemes-only (الخيار ب في القسم 6) لِحصول سريع على قيمة (~70% من تغطية quran-muaalem بِدون خادم)، ثم أضف رؤوس sifat لاحقاً لِلوصول لِـ ~90%.
