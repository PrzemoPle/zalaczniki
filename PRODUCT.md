# Załączniki — opis załączników do pozwu

## Użytkownik i zadanie
Adwokat przygotowuje pozew z dziesiątkami skanów jako załącznikami. Każdy pozew wymaga numerowanej
listy załączników („akt notarialny z dnia…, Rep. A nr…", „paragon fiskalny ze sklepu X z dnia…").
Program czyta pierwszą stronę każdego skanu, proponuje opis i datę, oznacza niepewne pozycje do ręcznego
sprawdzenia i oddaje gotową listę do skopiowania albo jako plik .txt.

## Platforma i ograniczenia
- Natywna aplikacja macOS (SwiftUI + AppKit), plik universal (Intel + Apple Silicon).
- Docelowy sprzęt: MacBook Air 2015 (Intel, 2 rdzenie), **macOS 12 Monterey** — to jest minimum.
- OCR: Apple Vision. Na macOS 12 bez słownika polskiego → reguły rozpoznawania ignorują ogonki.
- Domyślnie wszystko lokalnie (tajemnica adwokacka). Opcjonalnie Claude API (obraz 1. strony + tekst OCR),
  włączane świadomie w Ustawieniach, klucz w pęku kluczy.

## Język i ton
Polski, rzeczowy, kancelaryjny. Opisy w mianowniku, z polskimi znakami, bez dat w polu opisu.

## Założenia (wywnioskowane z briefu, do potwierdzenia)
- Kolejność załączników = kolejność plików (sortowanie naturalne po nazwie), z możliwością przestawiania.
- Brak zapisywania sesji między uruchomieniami — lista żyje do zamknięcia okna.
