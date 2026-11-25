import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import en from './locales/en.json'
import vi from './locales/vi.json'

export function pickLang(l?: string | null): 'vi' | 'en' { return l && l.toLowerCase().startsWith('vi') ? 'vi' : 'en' }
void i18n.use(initReactI18next).init({
  resources: { en: { translation: en }, vi: { translation: vi } },
  lng: pickLang(typeof navigator !== 'undefined' ? navigator.language : 'en'), fallbackLng: 'en', interpolation: { escapeValue: false },
})
export default i18n
