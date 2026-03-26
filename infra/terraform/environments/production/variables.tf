# ╔══════════════════════════════════════════════════════════════════╗
# ║  Full path: infra/terraform/environments/production/variables.tf ║
# ║  Status: 🆕 New — M7 Data Sovereignty Stub                      ║
# ╚══════════════════════════════════════════════════════════════════╝

# ── Data Sovereignty — MENA Region ───────────────────────────────────────
# يتحكم في تفعيل البنية التحتية في منطقة MENA (البحرين / الإمارات)
# القيمة الافتراضية false — لا يُفعَّل إلا بقرار صريح
# يُستخدم في: modules/networking, modules/cluster, modules/databases
variable "enable_mena_region" {
  description = "Enable MENA region for data sovereignty (Bahrain ap-southeast-3 / UAE me-central-1)"
  type        = bool
  default     = false
}
