import { useState, useEffect, useRef } from 'preact/hooks'
import { Clock, MapPin, Play } from 'lucide-preact'
import { CharacterCreation } from './CharacterCreation'
import './styles/spawn.css'

interface SpawnPoint {
  label: string
}

interface PlayerData {
  name?: string
  avatar?: string
  licenseClass?: string
  crew?: string
  playtime?: number
  stateText?: string
}

function formatPlaytime(seconds: number): string {
  const hrs = Math.floor(seconds / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  return `${String(hrs).padStart(2, '0')} HRS ${String(mins).padStart(2, '0')} MINS`
}

// Base theme (server.cfg spz_theme_* convars, pushed from spz-core) mapped
// onto this page's own CSS variable names (theme.css). Unknown/missing keys
// are a no-op since the stylesheet's own defaults still apply.
const THEME_VARS: Record<string, string> = {
  accent: '--color-primary',
  accent2: '--color-secondary',
  bg: '--bg-app',
  bg2: '--bg-card',
}
// rgba(...) glows/tints reference the accent as raw components so they can
// carry their own alpha — keep those in sync too.
const THEME_RGB_VARS: Record<string, string> = { accent: '--color-primary-rgb' }
function hexToRgbTriplet(hex?: string): string | null {
  const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex || '')
  return m ? `${parseInt(m[1], 16)}, ${parseInt(m[2], 16)}, ${parseInt(m[3], 16)}` : null
}
function applyTheme(theme?: Record<string, string>) {
  if (!theme) return
  for (const key in THEME_VARS) {
    if (theme[key]) document.documentElement.style.setProperty(THEME_VARS[key], theme[key])
  }
  for (const key in THEME_RGB_VARS) {
    const rgb = theme[key] && hexToRgbTriplet(theme[key])
    if (rgb) document.documentElement.style.setProperty(THEME_RGB_VARS[key], rgb)
  }
}

export function App() {
  const [view, setView] = useState<'none' | 'spawn' | 'creation'>('none')
  const [player, setPlayer] = useState<PlayerData>({})
  const [spawns, setSpawns] = useState<SpawnPoint[]>([])
  const [selected, setSelected] = useState(0)
  const [creationError, setCreationError] = useState<string | null>(null)
  const [cover, setCover] = useState(false)
  const [coverFading, setCoverFading] = useState(false)
  const listRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const handler = (e: MessageEvent) => {
      if (e.data.type === 'show') {
        setPlayer(e.data.playerData || {})
        setSpawns(e.data.spawns || [])
        setSelected(0)
        setView('spawn')
      } else if (e.data.type === 'showCharacterCreation') {
        setCreationError(null)
        setView('creation')
      } else if (e.data.type === 'characterCreationError') {
        setCreationError(e.data.message || 'An error occurred.')
      } else if (e.data.type === 'hide') {
        setView('none')
      } else if (e.data.type === 'showCover') {
        setCoverFading(false)
        setCover(true)
      } else if (e.data.type === 'hideCover') {
        // fade out, then unmount so the menu underneath is revealed
        setCoverFading(true)
        setTimeout(() => setCover(false), 750)
      } else if (e.data.type === 'theme') {
        applyTheme(e.data.theme)
      }
    }
    window.addEventListener('message', handler)
    return () => window.removeEventListener('message', handler)
  }, [])

  useEffect(() => {
    if (view !== 'spawn') return
    const onKey = (e: KeyboardEvent) => {
      const len = Math.max(1, spawns.length)
      if (e.key === 'ArrowRight' || e.key === 'd') setSelected(i => (i + 1) % len)
      else if (e.key === 'ArrowLeft' || e.key === 'a') setSelected(i => (i - 1 + len) % len)
      else if (e.key === 'Enter') doStart()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [view, spawns, selected])

  useEffect(() => {
    listRef.current?.querySelector('.active')?.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
  }, [selected])

  const doStart = () => {
    fetch(`https://${GetParentResourceName()}/startSpawn`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ index: selected + 1 }),
    }).catch(() => {})
    setView('none')
  }

  const licenseClass = player.licenseClass || 'D'

  return (
    <>
      {cover && <Cover fading={coverFading} />}

      {view === 'creation' && (
        <CharacterCreation serverError={creationError} onClearError={() => setCreationError(null)} />
      )}

      {view === 'spawn' && (
        <div class="sm-root">
          {/* Letterbox. Slides in from off-frame and crops the shot; every
              element below is anchored to these edges. */}
          <div class="sm-bar top" />
          <div class="sm-bar bottom" />
          <div class="sm-vignette" />

          <div class="sm-driver">
            <div class="sm-avatar">
              <img src={player.avatar || 'https://i.imgur.com/8NzA8m8.png'} alt="" />
            </div>
            <div class="sm-driver-text">
              <div class="sm-eyebrow"><i />{player.stateText || 'IDLE'}</div>
              <div class="sm-name">
                {player.name || 'Racer'}
                <span class="sm-chip">{licenseClass} Class</span>
                {player.crew && <span class="sm-chip muted">{player.crew}</span>}
              </div>
              <div class="sm-meta">
                <Clock size={11} color="var(--gray-600)" />
                {formatPlaytime(player.playtime || 0)}
              </div>
            </div>
          </div>

          <div class="sm-dest">
            <div class="sm-dest-main">
              <div class="sm-eyebrow" style={{ color: 'var(--gray-500)' }}>
                <MapPin size={11} />
                Deployment zone
              </div>

              {/* Keyed on the index so the name CUTS to the next one instead of
                  cross-fading — matches the camera language and reads faster. */}
              <div class="sm-dest-line" key={selected}>
                <span class="sm-index">
                  {String(selected + 1).padStart(2, '0')}
                  <small>/{String(Math.max(spawns.length, 1)).padStart(2, '0')}</small>
                </span>
                <span class="sm-place">{spawns[selected]?.label || 'Unknown'}</span>
              </div>

              <div class="sm-track">
                {spawns.map((_, i) => (
                  <div
                    key={i}
                    class={`sm-seg ${i === selected ? 'on' : ''}`}
                    onClick={() => setSelected(i)}
                  />
                ))}
              </div>
            </div>

            <div class="sm-commit">
              <button class="sm-go" onClick={doStart}>
                Spawn
                <Play size={17} fill="currentColor" />
              </button>
              <div class="sm-keys">
                <span class="sm-key">A</span>
                <span class="sm-key">D</span>
                navigate
                <span class="sm-sep">·</span>
                <span class="sm-key">↵</span>
                confirm
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  )
}

/* Full-screen branded cover — bridges the loading screen and the spawn menu so
   the raw world streaming / ped placement is never visible. */
function Cover({ fading }: { fading: boolean }) {
  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 99999,
        background:
          'radial-gradient(130% 90% at 50% 0%, rgba(var(--color-primary-rgb), 0.12), transparent 55%), radial-gradient(100% 100% at 50% 120%, rgba(var(--color-primary-rgb), 0.06), transparent 60%), #08090b',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        opacity: fading ? 0 : 1,
        transition: 'opacity 700ms ease',
        pointerEvents: fading ? 'none' : 'auto',
        fontFamily: "'Inter', sans-serif",
      }}
    >
      <style>{`
        @keyframes spzpulse{0%,100%{opacity:.85}50%{opacity:.35}}
        @keyframes spzrise{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}
        @keyframes spzblob{0%,100%{border-radius:42% 58% 60% 40% / 45% 45% 55% 55%}25%{border-radius:60% 40% 45% 55% / 55% 60% 40% 45%}50%{border-radius:45% 55% 48% 52% / 60% 45% 55% 40%}75%{border-radius:55% 45% 55% 45% / 42% 55% 45% 58%}}
        @keyframes spzblobspin{to{transform:rotate(360deg)}}
        @keyframes spzglow{0%,100%{box-shadow:0 0 40px 6px rgba(var(--color-primary-rgb),0.45),inset 0 -8px 20px rgba(120,40,0,0.5)}50%{box-shadow:0 0 66px 16px rgba(var(--color-primary-rgb),0.72),inset 0 -8px 20px rgba(120,40,0,0.5)}}
      `}</style>

      {/* faint grid / scanline texture */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          backgroundImage:
            'repeating-linear-gradient(0deg, rgba(255,255,255,0.015) 0px, rgba(255,255,255,0.015) 1px, transparent 1px, transparent 3px)',
          pointerEvents: 'none',
        }}
      />

      {/* morphing blob loader */}
      <div style={{ position: 'relative', width: '96px', height: '96px', marginBottom: '38px', zIndex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div
          style={{
            width: '82px',
            height: '82px',
            background: 'radial-gradient(circle at 34% 28%, #ffcf9c, var(--color-primary) 50%, #a63a00 100%)',
            borderRadius: '42% 58% 60% 40% / 45% 45% 55% 55%',
            animation: 'spzblob 6s ease-in-out infinite, spzblobspin 14s linear infinite, spzglow 2.4s ease-in-out infinite',
          }}
        />
      </div>

      {/* logo + tagline */}
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '14px', animation: 'spzrise .5s ease', zIndex: 1 }}>
        <img
          src="logo.png"
          alt="SPiceZ"
          style={{ height: '58px', width: 'auto', filter: 'drop-shadow(0 8px 40px rgba(var(--color-primary-rgb), 0.3))' }}
        />
        <div
          style={{
            fontFamily: 'monospace',
            fontSize: '10px',
            letterSpacing: '0.42em',
            textTransform: 'uppercase',
            color: 'rgba(255,255,255,0.35)',
          }}
        >
          Open-Source Racing Core
        </div>
      </div>

      <div
        style={{
          marginTop: '34px',
          fontFamily: 'monospace',
          fontSize: '11px',
          letterSpacing: '0.26em',
          textTransform: 'uppercase',
          color: 'rgba(255,255,255,0.42)',
          animation: 'spzpulse 1.8s ease-in-out infinite',
          zIndex: 1,
        }}
      >
        Preparing your session
      </div>

      {/* bottom brand strip */}
      <div
        style={{
          position: 'absolute',
          bottom: '28px',
          left: '50%',
          transform: 'translateX(-50%)',
          display: 'flex',
          alignItems: 'center',
          gap: '9px',
          zIndex: 1,
        }}
      >
        <span style={{ width: '6px', height: '6px', borderRadius: '50%', background: 'var(--color-primary)', boxShadow: '0 0 9px var(--color-primary)' }} />
        <span
          style={{
            fontFamily: 'monospace',
            fontSize: '9px',
            letterSpacing: '0.3em',
            textTransform: 'uppercase',
            color: 'rgba(255,255,255,0.28)',
          }}
        >
          SPiceZ-Core · FiveM
        </span>
      </div>
    </div>
  )
}

