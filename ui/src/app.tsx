import { useState, useEffect, useRef } from 'preact/hooks'
import { Clock, MapPin, Play, ChevronLeft, ChevronRight } from 'lucide-preact'
import { CharacterCreation } from './CharacterCreation'
import { Cover, COVER_EXIT_MS } from './Cover'
import { Cursor } from './components/Cursor'
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
  // Set the moment Spawn is pressed and cleared when the menu is next shown, so
  // a second press cannot fire a second spawn while the fade is running.
  const [committing, setCommitting] = useState(false)
  // Which spawn the pointer is over, if any. Held separately from `selected`
  // so hovering can PREVIEW a destination without committing the camera or the
  // index to it — moving the mouse across the track should not feel like it is
  // pressing every button it passes.
  const [peek, setPeek] = useState<number | null>(null)
  const listRef = useRef<HTMLDivElement>(null)

  // The cover's unmount is a timer, so it has to be cancellable: a `showCover`
  // arriving while one is pending would otherwise be torn down mid-life by the
  // previous exit finishing, and the screen it was put up to hide would be on
  // display. Held in a ref rather than state — nothing renders from it.
  const coverExit = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    const handler = (e: MessageEvent) => {
      if (e.data.type === 'show') {
        setPlayer(e.data.playerData || {})
        setSpawns(e.data.spawns || [])
        setSelected(0)
        setCommitting(false)
        setView('spawn')
      } else if (e.data.type === 'showCharacterCreation') {
        setCreationError(null)
        setView('creation')
      } else if (e.data.type === 'characterCreationError') {
        setCreationError(e.data.message || 'An error occurred.')
      } else if (e.data.type === 'hide') {
        setView('none')
      } else if (e.data.type === 'showCover') {
        if (coverExit.current) {
          clearTimeout(coverExit.current)
          coverExit.current = null
        }
        setCoverFading(false)
        setCover(true)
      } else if (e.data.type === 'hideCover') {
        // Run the sliced sweep, then unmount so the menu underneath is
        // revealed. COVER_EXIT_MS is owned by Cover.tsx — the panel stagger
        // decides how long this takes, so unmounting on a number typed in here
        // would cut the last panel off mid-sweep the first time anyone retimed
        // the animation.
        setCoverFading(true)
        if (coverExit.current) clearTimeout(coverExit.current)
        coverExit.current = setTimeout(() => {
          coverExit.current = null
          setCover(false)
        }, COVER_EXIT_MS)
      } else if (e.data.type === 'theme') {
        applyTheme(e.data.theme)
      }
    }
    window.addEventListener('message', handler)
    return () => window.removeEventListener('message', handler)
  }, [])

  const move = (delta: number) => {
    const len = Math.max(1, spawns.length)
    setSelected(i => (i + delta + len) % len)
  }

  useEffect(() => {
    if (view !== 'spawn') return

    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight' || e.key === 'd') move(1)
      else if (e.key === 'ArrowLeft' || e.key === 'a') move(-1)
      else if (e.key === 'Enter') doStart()
    }

    /*
     * Wheel cycles the destination.
     *
     * It is on `window` rather than on .sm-root because the root is
     * pointer-events: none — the shot underneath has to stay visible and
     * un-grabbed — and an element that does not take pointer events does not
     * get wheel events either. On this page nothing scrolls, so there is
     * nothing for a window-level handler to steal.
     *
     * Rate-limited: a trackpad flick is dozens of events and would otherwise
     * throw the camera through the whole list and back.
     */
    let lastWheel = 0
    const onWheel = (e: WheelEvent) => {
      const now = performance.now()
      if (now - lastWheel < 180) return
      lastWheel = now
      move(e.deltaY > 0 || e.deltaX > 0 ? 1 : -1)
    }

    window.addEventListener('keydown', onKey)
    window.addEventListener('wheel', onWheel, { passive: true })
    return () => {
      window.removeEventListener('keydown', onKey)
      window.removeEventListener('wheel', onWheel)
    }
  }, [view, spawns, selected])

  useEffect(() => {
    listRef.current?.querySelector('.active')?.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
  }, [selected])

  /*
   * Commit, but do NOT tear the menu down here.
   *
   * Hiding it on click dropped the player straight onto the raw camera shot for
   * the half second before the screen faded — menu gone, world visible, then
   * black. Lua fades out FIRST and sends `hide` on the other side of it, so the
   * menu is only ever removed behind a black screen. All this does is stop the
   * button being pressed twice while that plays out.
   */
  const doStart = () => {
    if (committing) return
    setCommitting(true)
    fetch(`https://${GetParentResourceName()}/startSpawn`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ index: selected + 1 }),
    }).catch(() => {})
  }

  const licenseClass = player.licenseClass || 'D'

  /*
   * Hovering the track PREVIEWS in the main readout rather than popping a
   * tooltip over it.
   *
   * There is nowhere for a tooltip to live here: the destination block is
   * pinned to the bottom letterbox with the name directly above the track and
   * the bar directly below it, so a label either covers the name it is
   * describing or hangs off the frame. Borrowing the readout costs no space,
   * puts the answer where the eye already is, and makes the track legible
   * without stepping the camera through every stop on the way to the one you
   * actually wanted.
   */
  const previewing = peek !== null && peek !== selected && peek < spawns.length
  const shown = previewing ? (peek as number) : selected

  return (
    <>
      {cover && <Cover fading={coverFading} />}

      {/* Mounted for both menus, not just the spawn screen. The two are one
          flow — creation hands straight over to spawn — and a pointer that
          changes identity halfway through it reads as two different products.
          It is suppressed while the cover is up and not yet leaving, where
          there is nothing to point at. */}
      <Cursor active={view !== 'none' && (!cover || coverFading)} />

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
              {/* The preview marker lives up here rather than inline with the
                  name: anything added to that row re-flows it, and the next
                  chevron jumping sideways every time the pointer crosses the
                  track is exactly the kind of twitch that makes a menu feel
                  cheap. This line is already its own row and has space to
                  spare. */}
              <div class="sm-eyebrow" style={{ color: 'var(--gray-500)' }}>
                <MapPin size={11} />
                Deployment zone
                {previewing && <span class="sm-peek-tag">preview</span>}
              </div>

              {/* The whole line is the control now, not just the thin track
                  below it. Keyed on the index so the name CUTS to the next one
                  instead of cross-fading — matches the camera language and
                  reads faster. */}
              <div class="sm-dest-line">
                <button
                  class="sm-nav"
                  onClick={() => move(-1)}
                  data-cursor-label="Prev"
                  aria-label="Previous spawn point"
                >
                  <ChevronLeft size={20} />
                </button>

                <div class={`sm-dest-name${previewing ? ' is-peek' : ''}`} key={selected}>
                  <span class="sm-index">
                    {String(shown + 1).padStart(2, '0')}
                    <small>/{String(Math.max(spawns.length, 1)).padStart(2, '0')}</small>
                  </span>
                  <span class="sm-place">{spawns[shown]?.label || 'Unknown'}</span>
                </div>

                <button
                  class="sm-nav"
                  onClick={() => move(1)}
                  data-cursor-label="Next"
                  aria-label="Next spawn point"
                >
                  <ChevronRight size={20} />
                </button>
              </div>

              {/*
                Each segment is a padded BUTTON wrapping a 3px bar. The bar is
                the whole thing you can see, and a 3px-tall click target on a
                moving camera shot is a target you miss — the hit area is sized
                for a hand, the mark stays sized for the composition.
              */}
              <div class="sm-track" onMouseLeave={() => setPeek(null)}>
                {spawns.map((s, i) => (
                  <button
                    key={i}
                    class={`sm-seg-hit${i === selected ? ' on' : ''}`}
                    onClick={() => setSelected(i)}
                    onMouseEnter={() => setPeek(i)}
                    aria-label={s.label}
                  >
                    <i />
                  </button>
                ))}
              </div>
            </div>

            <div class="sm-commit">
              <button
                class={`sm-go${committing ? ' is-committing' : ''}`}
                onClick={doStart}
                disabled={committing}
                data-cursor-label={committing ? '' : 'Deploy'}
              >
                {committing ? 'Spawning' : 'Spawn'}
                <Play size={17} fill="currentColor" />
              </button>
              {/* Both input schemes, because both now work: the mouse is no
                  longer a second-class way to drive this screen. */}
              <div class="sm-keys">
                <span class="sm-key">A</span>
                <span class="sm-key">D</span>
                navigate
                <span class="sm-sep">·</span>
                <span class="sm-key">↵</span>
                confirm
                <span class="sm-sep">·</span>
                <span class="sm-key sm-key-wheel" aria-hidden="true" />
                scroll
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
