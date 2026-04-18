# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| latest  | ✅ Yes             |
| < 1.0.0 | ❌ No              |

## Reporting a Vulnerability

**لا تفتح Issue عام لأي ثغرة أمنية.**

إذا اكتشفت ثغرة أمنية، أرسل تقريراً عبر:

1. **GitHub Security Advisories** (مفضّل):
   - افتح: `Security → Advisories → Report a vulnerability`
   - الرابط: `https://github.com/scorpiontrader16-ai/AmniX-Finance/security/advisories/new`

## ماذا تُضمّن في التقرير

- وصف الثغرة
- خطوات إعادة الإنتاج
- التأثير المحتمل
- اقتراح الإصلاح (اختياري)

## وقت الاستجابة

| المرحلة              | المدة      |
|----------------------|------------|
| تأكيد الاستلام       | 48 ساعة   |
| تقييم الخطورة        | 5 أيام     |
| إصلاح Critical       | 7 أيام     |
| إصلاح High           | 30 يوم     |
| إصلاح Medium/Low     | 90 يوم     |

## Scope

### في النطاق ✅
- Go Ingestion Service (`services/ingestion/`)
- Rust Processing Service (`services/processing/`)
- Kubernetes manifests (`k8s/`)
- Terraform infrastructure (`infra/terraform/`)
- GitHub Actions workflows (`.github/workflows/`)
- API endpoints (gRPC + HTTP)

### خارج النطاق ❌
- Third-party dependencies (أبلّغ المكتبة مباشرة)
- Denial of Service attacks
- Social engineering

## Security Measures

هذا المشروع يستخدم:
- **Gitleaks** — منع تسريب الـ secrets في Git
- **Trivy** — فحص الـ dependencies والـ Docker images
- **CodeQL** — تحليل ثابت للكود
- **Semgrep** — كشف الأنماط الأمنية الخطيرة
- **Kyverno** — Zero-Trust policies على Kubernetes
- **mTLS** — تشفير كل الاتصالات بين الخدمات
- **External Secrets Operator** — إدارة الـ secrets عبر Vault
- **Cosign** — توقيع Docker images
