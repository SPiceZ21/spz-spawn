/** @jsx h */
const { h, Fragment, createContext } = preact;
const { useState, useRef, useEffect, useCallback, useMemo, useContext } = preactHooks;

/* ---------- Icon (Lucide via global) ---------- */
function Icon({ name, size = 14, strokeWidth = 1.75, ...rest }) {
  const ref = useRef(null);
  useEffect(() => {
    if (window.lucide && ref.current) window.lucide.createIcons({ nameAttr: 'data-lucide', icons: window.lucide.icons, attrs: {}, });
  }, [name]);
  return (
    <i
      ref={ref}
      data-lucide={name}
      style={{ width: size, height: size, display: 'inline-flex', strokeWidth }}
      {...rest}
    />
  );
}

/* ---------- Button ---------- */
function Button({ variant = 'default', size = 'default', icon, iconRight, children, ...rest }) {
  return (
    <button className="spz-btn" data-variant={variant} data-size={size} {...rest}>
      {icon && <Icon name={icon} />}
      {children}
      {iconRight && <Icon name={iconRight} />}
    </button>
  );
}

/* ---------- Input / Textarea / Select ---------- */
function Input(props) { return <input className="spz-input" {...props} />; }
function Textarea(props) { return <textarea className="spz-textarea" {...props} />; }
function Select({ children, ...rest }) {
  return <select className="spz-select" {...rest}>{children}</select>;
}
function Field({ label, helper, children, mono = true }) {
  return (
    <div className="spz-input-group">
      {label && <label className="spz-label">{label}</label>}
      {children}
      {helper && <div className="spz-helper">{helper}</div>}
    </div>
  );
}

/* ---------- Card ---------- */
function Card({ armed, children, style, className = '', ...rest }) {
  return (
    <div className={`spz-card ${className}`} data-armed={armed ? 'true' : undefined} style={style} {...rest}>
      {children}
    </div>
  );
}
function CardHeader({ title, desc, children }) {
  return (
    <div className="spz-card-header">
      <div>
        {title && <h3 className="spz-card-title">{title}</h3>}
        {desc && <div className="spz-card-desc">{desc}</div>}
      </div>
      {children}
    </div>
  );
}

/* ---------- Badge ---------- */
function Badge({ variant, children, ...rest }) {
  return <span className="spz-badge" data-variant={variant} {...rest}>{children}</span>;
}

/* ---------- Kbd ---------- */
function Kbd({ children }) { return <span className="spz-kbd">{children}</span>; }

/* ---------- Switch ---------- */
function Switch({ checked, onChange, ...rest }) {
  const [_on, _set] = useState(!!checked);
  const on = checked !== undefined ? checked : _on;
  const toggle = () => {
    const next = !on;
    if (checked === undefined) _set(next);
    onChange?.(next);
  };
  return (
    <button
      role="switch"
      aria-checked={on}
      className="spz-switch"
      data-on={on ? 'true' : 'false'}
      onClick={toggle}
      {...rest}
    />
  );
}

/* ---------- Checkbox ---------- */
function Checkbox({ checked, onChange, ...rest }) {
  const [_on, _set] = useState(!!checked);
  const on = checked !== undefined ? checked : _on;
  const toggle = () => {
    const next = !on;
    if (checked === undefined) _set(next);
    onChange?.(next);
  };
  return (
    <span role="checkbox" aria-checked={on} className="spz-checkbox" data-on={on} onClick={toggle} {...rest} />
  );
}

/* ---------- Radio group ---------- */
function RadioGroup({ value, onChange, options }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {options.map((opt) => (
        <label key={opt.value} style={{ display: 'inline-flex', alignItems: 'center', gap: 8, cursor: 'pointer', fontSize: 13, color: 'var(--spz-fg-2)' }}>
          <span className="spz-radio" data-on={value === opt.value} onClick={() => onChange?.(opt.value)} />
          {opt.label}
        </label>
      ))}
    </div>
  );
}

/* ---------- Slider ---------- */
function Slider({ value, onChange, min = 0, max = 100, step = 1 }) {
  const [_v, _set] = useState(value ?? min);
  const v = value !== undefined ? value : _v;
  const trackRef = useRef(null);
  const setFromEvent = (e) => {
    const r = trackRef.current.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
    let next = min + ratio * (max - min);
    next = Math.round(next / step) * step;
    next = Math.max(min, Math.min(max, next));
    if (value === undefined) _set(next);
    onChange?.(next);
  };
  const onDown = (e) => {
    setFromEvent(e);
    const move = (ev) => setFromEvent(ev);
    const up = () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', up); };
    window.addEventListener('mousemove', move);
    window.addEventListener('mouseup', up);
  };
  const pct = ((v - min) / (max - min)) * 100;
  return (
    <div className="spz-slider" ref={trackRef} onMouseDown={onDown}>
      <div className="spz-slider-track">
        <div className="spz-slider-fill" style={{ width: `${pct}%` }} />
      </div>
      <div className="spz-slider-thumb" style={{ left: `${pct}%` }} />
    </div>
  );
}

/* ---------- Progress ---------- */
function Progress({ value = 0 }) {
  return <div className="spz-progress"><div className="spz-progress-fill" style={{ width: `${Math.max(0, Math.min(100, value))}%` }} /></div>;
}

/* ---------- Tabs ---------- */
function Tabs({ value, onChange, items }) {
  const [_v, _set] = useState(items[0]?.value);
  const v = value ?? _v;
  return (
    <div className="spz-tabs">
      {items.map((it) => (
        <button
          key={it.value}
          className="spz-tab"
          data-active={v === it.value ? 'true' : 'false'}
          onClick={() => { if (value === undefined) _set(it.value); onChange?.(it.value); }}
        >
          {it.label}
        </button>
      ))}
    </div>
  );
}

/* ---------- Segmented control ---------- */
function Segment({ value, onChange, items }) {
  const [_v, _set] = useState(items[0]?.value);
  const v = value ?? _v;
  return (
    <div className="spz-segment">
      {items.map((it) => (
        <button
          key={it.value}
          className="spz-segment-item"
          data-active={v === it.value}
          onClick={() => { if (value === undefined) _set(it.value); onChange?.(it.value); }}
        >
          {it.label}
        </button>
      ))}
    </div>
  );
}

/* ---------- Avatar ---------- */
function Avatar({ initials, src, size = 28 }) {
  return (
    <span className="spz-avatar" style={{ width: size, height: size, fontSize: size <= 24 ? 10 : 11 }}>
      {src ? <img src={src} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : initials}
    </span>
  );
}

/* ---------- Live dot ---------- */
function Live({ color, children = 'Live' }) { return <span className="spz-live" data-color={color}>{children}</span>; }

/* ---------- Alert ---------- */
function Alert({ variant = 'info', icon, title, children }) {
  const defaultIcon = { info: 'info', success: 'check-circle-2', warn: 'triangle-alert', danger: 'octagon-alert', brand: 'flag' }[variant] || 'info';
  return (
    <div className="spz-alert" data-variant={variant}>
      <Icon name={icon || defaultIcon} size={16} />
      <div>
        {title && <p className="spz-alert-title">{title}</p>}
        {children && <p className="spz-alert-desc">{children}</p>}
      </div>
    </div>
  );
}

/* ---------- Breadcrumb ---------- */
function Breadcrumb({ items }) {
  return (
    <nav className="spz-breadcrumb">
      {items.map((it, i) => (
        <Fragment key={i}>
          {i > 0 && <span className="spz-breadcrumb-sep">/</span>}
          {i === items.length - 1 ? <span className="spz-breadcrumb-current">{it}</span> : <a href="#">{it}</a>}
        </Fragment>
      ))}
    </nav>
  );
}

/* ---------- Dropdown menu (simple) ---------- */
function DropdownMenu({ trigger, children }) {
  const [open, setOpen] = useState(false);
  const ref = useRef(null);
  useEffect(() => {
    const onDoc = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    document.addEventListener('mousedown', onDoc);
    return () => document.removeEventListener('mousedown', onDoc);
  }, []);
  return (
    <div ref={ref} style={{ position: 'relative', display: 'inline-block' }}>
      <span onClick={() => setOpen(o => !o)}>{trigger}</span>
      {open && (
        <div className="spz-popover" style={{ position: 'absolute', top: 'calc(100% + 4px)', right: 0, zIndex: 20 }}>
          {children}
        </div>
      )}
    </div>
  );
}
function MenuItem({ icon, shortcut, children, onClick }) {
  return (
    <div className="spz-menu-item" onClick={onClick}>
      {icon && <Icon name={icon} />}
      <span>{children}</span>
      {shortcut && <span className="spz-menu-item-shortcut">{shortcut}</span>}
    </div>
  );
}
function MenuLabel({ children }) { return <div className="spz-menu-label">{children}</div>; }
function MenuDivider() { return <div className="spz-menu-divider" />; }

/* ---------- Toast / Notification ---------- */
const ToastCtx = createContext(null);
function ToastProvider({ children }) {
  const [toasts, setToasts] = useState([]);
  const dismiss = useCallback((id) => {
    setToasts((arr) => arr.map(t => t.id === id ? { ...t, leaving: true } : t));
    setTimeout(() => setToasts((arr) => arr.filter(t => t.id !== id)), 220);
  }, []);
  const push = useCallback((toast) => {
    const id = Math.random().toString(36).slice(2);
    const dur = toast.duration ?? 4000;
    setToasts((arr) => [...arr, { id, ...toast, dur }]);
    if (dur > 0) setTimeout(() => dismiss(id), dur);
    return id;
  }, [dismiss]);
  return (
    <ToastCtx.Provider value={{ push, dismiss }}>
      {children}
      <div className="spz-toast-stack">
        {toasts.map((t) => <Toast key={t.id} {...t} onClose={() => dismiss(t.id)} />)}
      </div>
    </ToastCtx.Provider>
  );
}
function useToast() { return useContext(ToastCtx); }
function Toast({ variant = 'info', icon, eyebrow, title, description, mono, onClose, dur, leaving }) {
  const defaultIcon = { info: 'info', success: 'check-circle-2', warn: 'triangle-alert', danger: 'octagon-alert', brand: 'flag' }[variant] || 'info';
  useEffect(() => { if (window.lucide) window.lucide.createIcons(); }, []);
  return (
    <div className="spz-toast" data-variant={variant} data-leaving={leaving ? 'true' : undefined} style={{ '--_dur': `${dur}ms` }}>
      <Icon name={icon || defaultIcon} size={16} />
      <div>
        {eyebrow && <div className="spz-toast-eyebrow">{eyebrow}</div>}
        {title && <p className="spz-toast-title">{title}</p>}
        {description && <p className="spz-toast-desc">{description}</p>}
        {mono && <div className="spz-toast-mono">{mono}</div>}
      </div>
      <button className="spz-toast-close" onClick={onClose} aria-label="Close"><Icon name="x" size={12} /></button>
      {dur > 0 && <span className="spz-toast-progress" />}
    </div>
  );
}

/* ---------- Kbd group / Keycap ---------- */
function KbdGroup({ keys }) {
  return (
    <span className="spz-kbd-group">
      {keys.map((k, i) => (
        <React.Fragment key={i}>
          {i > 0 && <span className="spz-kbd-plus">+</span>}
          <Kbd>{k}</Kbd>
        </React.Fragment>
      ))}
    </span>
  );
}
function Keycap({ children, pressed, ...rest }) {
  return <span className="spz-keycap" data-pressed={pressed ? 'true' : undefined} {...rest}>{children}</span>;
}

/* ---------- Table ---------- */
function Table({ children }) { return <table className="spz-table">{children}</table>; }

/* ---------- Tooltip (hover only) ---------- */
function Tooltip({ label, children }) {
  const [show, setShow] = useState(false);
  return (
    <span style={{ position: 'relative', display: 'inline-flex' }} onMouseEnter={() => setShow(true)} onMouseLeave={() => setShow(false)}>
      {children}
      {show && <span className="spz-tooltip" style={{ bottom: 'calc(100% + 6px)', left: '50%', transform: 'translateX(-50%)' }}>{label}</span>}
    </span>
  );
}

/* ---------- Telemetry tile (motorsport flavor) ---------- */
function TelemetryTile({ label, value, unit, delta, color = 'orange' }) {
  return (
    <div style={{
      background: 'var(--spz-surface-1)',
      border: '1px solid var(--spz-line)',
      borderRadius: 6,
      padding: '12px 14px',
      display: 'flex', flexDirection: 'column', gap: 6,
      minWidth: 140,
    }}>
      <div className="spz-eyebrow">{label}</div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 4 }}>
        <span style={{ fontFamily: 'var(--spz-font-mono)', fontSize: 22, fontWeight: 600, color: 'var(--spz-fg-1)', fontVariantNumeric: 'tabular-nums' }}>{value}</span>
        {unit && <span style={{ fontFamily: 'var(--spz-font-mono)', fontSize: 11, color: 'var(--spz-fg-3)', textTransform: 'uppercase', letterSpacing: '0.12em' }}>{unit}</span>}
      </div>
      {delta !== undefined && (
        <div style={{
          fontFamily: 'var(--spz-font-mono)', fontSize: 11, fontVariantNumeric: 'tabular-nums',
          color: delta < 0 ? 'var(--spz-success)' : delta > 0 ? 'var(--spz-danger)' : 'var(--spz-fg-3)',
        }}>
          {delta > 0 ? '+' : ''}{delta}
        </div>
      )}
    </div>
  );
}

/* ---------- Lap row (telemetry list row) ---------- */
function LapRow({ lap, time, sectors, status }) {
  const statusColor = status === 'pb' ? 'var(--spz-purple)' : status === 'best' ? 'var(--spz-success)' : 'var(--spz-fg-2)';
  return (
    <tr>
      <td><span className="spz-mono" style={{ color: 'var(--spz-fg-3)' }}>L{String(lap).padStart(2, '0')}</span></td>
      <td><span className="spz-mono" style={{ color: statusColor, fontWeight: 600 }}>{time}</span></td>
      {sectors.map((s, i) => (
        <td key={i}><span className="spz-mono" style={{ color: s.fastest ? 'var(--spz-purple)' : 'var(--spz-fg-2)' }}>{s.t}</span></td>
      ))}
      <td>{status && <Badge variant={status === 'pb' ? 'purple' : status === 'best' ? 'success' : undefined}>{status === 'pb' ? 'PB' : status}</Badge>}</td>
    </tr>
  );
}

Object.assign(window, {
  Icon, Button, Input, Textarea, Select, Field,
  Card, CardHeader,
  Badge, Kbd, Switch, Checkbox, RadioGroup, Slider, Progress,
  Tabs, Segment, Avatar, Live, Alert, Breadcrumb,
  DropdownMenu, MenuItem, MenuLabel, MenuDivider,
  Table, Tooltip, TelemetryTile, LapRow,
  ToastProvider, useToast, Toast, KbdGroup, Keycap,
});
