# Konfiguracja Git dla repo z cartami Pico-8

Krótko: dodane pliki ` .gitignore` i ` .gitattributes` aby śledzić carty (`.p8`) poprawnie i ignorować lokalne kopie zapasowe oraz logi.

Szybki start (w terminalu w katalogu projektu):

```powershell
git init
git add .
git commit -m "Initial commit: add git config for Pico-8 carts"
git branch -M main
git remote add origin <url-do-repo>
git push -u origin main
```

Opcjonalnie: Git LFS dla obrazów (zalecane jeśli masz duże PNG):

```powershell
git lfs install
git lfs track "*.png"
git lfs track "*.p8.png"
git add .gitattributes
git add --all
git commit -m "Add Git LFS tracking for images"
git push
```

Uwagi:
- Katalog `backup/` i inne lokalne dane są ignorowane przez ` .gitignore`.
- ` .gitattributes` ustawia `*.p8` jako tekst z LF, co ułatwia porównania i mergety.
- Jeśli chcesz, mogę dodać przykładowy `pre-commit` hook (np. walidacja składni `.p8`).
