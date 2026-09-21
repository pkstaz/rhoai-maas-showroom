;(function () {
  var BASH_LANGS = { bash: true, sh: true, shell: true, console: true }

  function isBashBlock (block) {
    var code = block.querySelector('pre code, pre')
    if (!code) return false
    var lang = (code.getAttribute('data-lang') || '').toLowerCase()
    if (BASH_LANGS[lang]) return true
    var cls = code.className || ''
    return /(^|\s)language-(bash|sh|shell|console)(\s|$)/.test(cls)
  }

  function sourceText (block) {
    var pre = block.querySelector('pre')
    if (!pre) return ''
    return (pre.innerText || pre.textContent || '').replace(/\n$/, '')
  }

  function setCopied (btn) {
    var original = btn.getAttribute('data-label') || 'Copiar'
    btn.textContent = 'Copiado'
    btn.classList.add('is-copied')
    window.setTimeout(function () {
      btn.textContent = original
      btn.classList.remove('is-copied')
    }, 1600)
  }

  function copyText (text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text)
    }
    return new Promise(function (resolve, reject) {
      var area = document.createElement('textarea')
      area.value = text
      area.setAttribute('readonly', '')
      area.style.position = 'absolute'
      area.style.left = '-9999px'
      document.body.appendChild(area)
      area.select()
      try {
        document.execCommand('copy')
        resolve()
      } catch (err) {
        reject(err)
      } finally {
        document.body.removeChild(area)
      }
    })
  }

  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('.listingblock').forEach(function (block) {
      if (!isBashBlock(block)) return
      if (block.querySelector('.copy-button')) return

      var btn = document.createElement('button')
      btn.type = 'button'
      btn.className = 'copy-button'
      btn.setAttribute('data-label', 'Copiar')
      btn.setAttribute('aria-label', 'Copiar comando')
      btn.textContent = 'Copiar'
      block.appendChild(btn)

      btn.addEventListener('click', function () {
        copyText(sourceText(block)).then(function () {
          setCopied(btn)
        }).catch(function () {
          btn.textContent = 'Error'
        })
      })
    })
  })
})()
