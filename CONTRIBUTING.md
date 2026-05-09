# Contributing

Contributions, issues, and feature requests are welcome.

---

## Development setup

```bash
git clone https://github.com/AliHaidry/azure-finops-dashboard.git
cd azure-finops-dashboard

# Collector
cd collector
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt

# Dashboard
cd ../dashboard
npm install
```

---

## Making changes

1. Fork the repo and create a branch: `git checkout -b feat/your-feature`
2. Make your changes
3. Run tests: `pytest collector/tests/` and `npm test`
4. Update documentation if needed
5. Open a pull request — include what changed and why

---

## Commit message format

```
type: short description

type = feat | fix | docs | refactor | test | chore
```

Examples:
```
feat: add Azure Function deployment for collector
fix: handle missing team tag gracefully
docs: add troubleshooting section to runbook
```

---

## Author

**Syed Muhammad Ali Haidry** · [alihaidry-devops.website](https://alihaidry-devops.website)
